"""
account/proof_views.py

Payment-proof endpoints (all under /api/v1/auth/):

  POST /payments/<payment_id>/proof/                      upload a proof (multipart: proof_image, tx_hash, notes)
  GET  /payments/<payment_id>/proofs/                     list every proof the user sent for this payment
  GET  /payments/<payment_id>/proofs/<proof_id>/image/    the user's own proof image (JWT-authenticated)

Why the upload is built this way
--------------------------------
The old version replied 202 straight away and did the Cloudinary upload on a
background thread. On shared hosting (Passenger / LiteSpeed) the worker
process is frozen or recycled once the response has gone out, so that thread
very often never finished: the app said "Proof submitted" but no image ever
arrived, and every failure was swallowed silently.

Now the image is written to the server's own disk INSIDE the request, before
we reply (a fast local write). Only once it is safely stored do we answer
201. Mirroring to Cloudinary and emailing the admin still happen in the
background, but they are extras: if they die, the proof is not lost, the
admin sees the local copy, and `python manage.py push_payment_proofs` (or
the admin action) retries the Cloudinary mirror.
"""

import logging
import mimetypes
import os
import threading
import time
import uuid

from django.conf import settings
from django.core.files.base import ContentFile
from django.db import close_old_connections, connection
from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404
from django.template.loader import render_to_string

from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.negotiation import BaseContentNegotiation
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import CryptoPayment, PaymentProof

logger = logging.getLogger(__name__)

MAX_PROOF_BYTES = 10 * 1024 * 1024  # 10 MB
ALLOWED_FORMATS = {"JPEG": ".jpg", "PNG": ".png", "WEBP": ".webp", "GIF": ".gif", "BMP": ".bmp"}


# ─────────────────────────────────────────────────────────────────────────────
# Serialisation
# ─────────────────────────────────────────────────────────────────────────────

def serialize_proof(proof):
    return {
        "id": proof.id,
        "submitted_at": proof.submitted_at,
        "tx_hash": proof.tx_hash,
        "notes": proof.notes,
        "has_image": proof.has_image,
        # Relative to the API base (…/api/v1). The app adds its own base URL
        # and sends its Bearer token to load it.
        "image_path": (
            f"/auth/payments/{proof.payment.payment_id}/proofs/{proof.id}/image/"
            if proof.has_image else None
        ),
        "original_filename": proof.original_filename,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Background work (best effort — never required for the proof to be safe)
# ─────────────────────────────────────────────────────────────────────────────

def _run_in_background(fn, *args):
    """Run fn(*args) on a daemon thread with its own, cleanly closed DB connection."""
    def runner():
        close_old_connections()
        try:
            fn(*args)
        except Exception:
            logger.exception("Background task %s failed", getattr(fn, "__name__", fn))
        finally:
            connection.close()

    threading.Thread(target=runner, daemon=True).start()


def push_proof_to_cloudinary(proof_id):
    """
    Mirror the locally stored proof image to Cloudinary.
    Safe to call repeatedly (admin action / management command use it too).
    Returns True on success.
    """
    try:
        proof = PaymentProof.objects.get(id=proof_id)
    except PaymentProof.DoesNotExist:
        return False

    if proof.proof_image:
        if proof.upload_status != PaymentProof.STATUS_UPLOADED:
            PaymentProof.objects.filter(id=proof_id).update(
                upload_status=PaymentProof.STATUS_UPLOADED, upload_error="",
            )
        return True
    if not proof.local_image:
        return False

    last_error = ""
    for attempt in range(3):
        try:
            with proof.local_image.open("rb") as fh:
                data = fh.read()
            name = os.path.basename(proof.local_image.name)
            proof.proof_image.save(name, ContentFile(data), save=False)
            PaymentProof.objects.filter(id=proof_id).update(
                proof_image=proof.proof_image.name,
                upload_status=PaymentProof.STATUS_UPLOADED,
                upload_error="",
            )
            return True
        except Exception as exc:  # network blip, bad credentials, …
            last_error = f"{type(exc).__name__}: {exc}"
            logger.warning("Cloudinary upload of proof %s failed (attempt %s): %s",
                           proof_id, attempt + 1, last_error)
            time.sleep(2 ** attempt)

    PaymentProof.objects.filter(id=proof_id).update(
        upload_status=PaymentProof.STATUS_FAILED,
        upload_error=last_error[:2000],
    )
    return False


def _notify_admin_new_proof(proof_id):
    from .views import _send_desktop_email  # existing SMTP helper

    proof = PaymentProof.objects.select_related("payment", "payment__user").get(id=proof_id)
    payment = proof.payment
    site = getattr(settings, "SITE_URL", "https://realfaceai.app")
    admin_url = f"{site}/admin/account/cryptopayment/{payment.id}/change/"
    admin_emails = getattr(settings, "ADMIN_EMAILS", None) or [settings.ADMIN_EMAIL]

    _send_desktop_email(
        to_email=admin_emails,
        subject=f"[Action Required] New Payment Proof — {payment.payment_id}",
        html_body=render_to_string("emails/admin_payment_proof.html", {
            "site_url": site,
            "payment": payment,
            "proof": proof,
            "admin_url": admin_url,
            "rows": [
                ("Payment ID", payment.payment_id, "mono"),
                ("User", payment.user.email, ""),
                ("Amount", f"${payment.amount_usd}", "accent"),
                ("Currency", payment.currency.upper(), ""),
                ("Wallet", payment.wallet_address or "—", "mono"),
                ("TX hash", proof.tx_hash or "—", "mono"),
                ("Notes", proof.notes or "—", ""),
                ("Proofs sent", str(payment.proofs.count()), ""),
            ],
        }),
    )


# ─────────────────────────────────────────────────────────────────────────────
# Upload
# ─────────────────────────────────────────────────────────────────────────────

def _validate_image(upload):
    """Returns (bytes, extension) or raises ValueError with a user-facing message."""
    if upload.size and upload.size > MAX_PROOF_BYTES:
        raise ValueError("Image is too large. Maximum size is 10 MB.")

    data = upload.read()
    if not data:
        raise ValueError("The uploaded file is empty.")
    if len(data) > MAX_PROOF_BYTES:
        raise ValueError("Image is too large. Maximum size is 10 MB.")

    try:
        from io import BytesIO
        from PIL import Image
        img = Image.open(BytesIO(data))
        fmt = (img.format or "").upper()
        img.verify()
    except Exception:
        raise ValueError("That file isn't a valid image. Please upload a JPG, PNG or WEBP screenshot.")

    if fmt not in ALLOWED_FORMATS:
        raise ValueError("Unsupported image type. Please upload a JPG, PNG or WEBP screenshot.")
    return data, ALLOWED_FORMATS[fmt]


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def submit_payment_proof(request, payment_id):
    payment = get_object_or_404(CryptoPayment, payment_id=payment_id, user=request.user)

    if payment.status == CryptoPayment.STATUS_CONFIRMED:
        return Response({"error": "This payment is already confirmed."}, status=400)
    if payment.status in (CryptoPayment.STATUS_FAILED, CryptoPayment.STATUS_EXPIRED):
        return Response({"error": f"This payment is {payment.status}. Please start a new one."}, status=400)

    # ── Idempotency: a retried request (dropped connection) returns the
    #    proof we already stored instead of creating a duplicate.
    idempotency_key = (request.headers.get("Idempotency-Key") or "").strip()[:64]
    if idempotency_key:
        existing = PaymentProof.objects.filter(payment=payment, idempotency_key=idempotency_key).first()
        if existing is not None and existing.has_image:
            return Response({
                "detail": "Proof received.",
                "proof": serialize_proof(existing),
                "proof_count": payment.proofs.count(),
            }, status=200)

    upload = request.FILES.get("proof_image")
    if not upload:
        return Response({"error": "Please attach a screenshot of your payment."}, status=400)

    try:
        data, ext = _validate_image(upload)
    except ValueError as exc:
        return Response({"error": str(exc)}, status=400)

    tx_hash = (request.data.get("tx_hash") or "").strip()[:255]
    notes = (request.data.get("notes") or "").strip()[:2000]

    # ── Store the image on local disk NOW, inside the request ───────────────
    try:
        proof = PaymentProof(
            payment=payment,
            tx_hash=tx_hash,
            notes=notes,
            original_filename=(upload.name or "")[:255],
            upload_status=PaymentProof.STATUS_PENDING,
            idempotency_key=idempotency_key or None,
        )
        stored_name = f"{payment.payment_id}_{uuid.uuid4().hex[:10]}{ext}"
        proof.local_image.save(stored_name, ContentFile(data), save=False)
        proof.save()
    except Exception:
        logger.exception("Could not store payment proof for %s", payment.payment_id)
        return Response(
            {"error": "We couldn't save your image on our server. Please try again."},
            status=500,
        )

    # ── Extras: Cloudinary mirror + admin email (best effort) ────────────────
    _run_in_background(push_proof_to_cloudinary, proof.id)
    _run_in_background(_notify_admin_new_proof, proof.id)

    return Response({
        "detail": "Proof received. Our team will review it shortly.",
        "proof": serialize_proof(proof),
        "proof_count": payment.proofs.count(),
    }, status=201)


# ─────────────────────────────────────────────────────────────────────────────
# List + view (user's own proofs only)
# ─────────────────────────────────────────────────────────────────────────────

@api_view(["GET"])
@permission_classes([IsAuthenticated])
def list_payment_proofs(request, payment_id):
    payment = get_object_or_404(CryptoPayment, payment_id=payment_id, user=request.user)
    proofs = list(payment.proofs.select_related("payment").all())
    return Response({
        "payment_id": payment.payment_id,
        "status": payment.status,
        "can_upload": payment.status in (CryptoPayment.STATUS_WAITING, CryptoPayment.STATUS_CONFIRMING),
        "count": len(proofs),
        "results": [serialize_proof(p) for p in proofs],
    })


def open_proof_image(proof):
    """FileResponse for a proof's image (local copy first, Cloudinary as fallback)."""
    if proof.local_image:
        try:
            fh = proof.local_image.open("rb")
            ctype = mimetypes.guess_type(proof.local_image.name)[0] or "application/octet-stream"
            return FileResponse(fh, content_type=ctype)
        except (FileNotFoundError, OSError):
            logger.warning("Local proof image missing for proof %s", proof.id)

    if proof.proof_image:
        import requests
        try:
            r = requests.get(proof.proof_image.url, timeout=15)
            if r.ok:
                from django.http import HttpResponse
                return HttpResponse(r.content, content_type=r.headers.get("Content-Type", "image/jpeg"))
        except Exception:
            logger.warning("Cloudinary fetch failed for proof %s", proof.id)

    raise Http404("Image not available.")


class _IgnoreAcceptHeader(BaseContentNegotiation):
    """Image clients send Accept: image/*; don't let DRF answer 406 for that."""
    def select_parser(self, request, parsers):
        return parsers[0] if parsers else None

    def select_renderer(self, request, renderers, format_suffix=None):
        return (renderers[0], renderers[0].media_type)


class ProofImageView(APIView):
    permission_classes = [IsAuthenticated]
    content_negotiation_class = _IgnoreAcceptHeader

    def get(self, request, payment_id, proof_id):
        proof = get_object_or_404(
            PaymentProof.objects.select_related("payment"),
            id=proof_id, payment__payment_id=payment_id, payment__user=request.user,
        )
        return open_proof_image(proof)