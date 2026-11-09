"""
payments views
==============

Payment flow (manual crypto / bank transfer):
  POST /api/v1/auth/payments/create/     → records a PENDING payment, returns payment instructions
  GET  /api/v1/auth/<id>/status/         → Flutter polls this (stays "waiting" until admin confirms).
                                           Also returns the full instructions (wallet, amount) so the
                                           app can reopen them from payment history.

IMPORTANT: nothing slow (SMTP, Cloudinary, …) may run inside a request here.
`transaction.on_commit()` runs its callback IMMEDIATELY when there is no
open transaction (this project doesn't set ATOMIC_REQUESTS), so the old
"notify admin" email was actually sent synchronously before the response —
when the SMTP server was slow the app sat waiting and "Continue" appeared to
do nothing, even though the payment row had already been saved.

Admin confirms manual payments via the Django admin action "Confirm selected payments".
When confirmed, credits are added atomically and the user receives a Resend email.
"""

import json
import logging
import secrets

from decimal import Decimal
from django.conf import settings
from django.template.loader import render_to_string
from django.db import transaction
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator

import requests as http_requests

from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

import random
import threading
from datetime import timedelta

from django.db import close_old_connections, connection
from django.db.models import Count, Max, OuterRef, Subquery

from .models import CryptoPayment, UserProfile, CryptoWallet, FiatCurrency, PaymentProof

logger = logging.getLogger(__name__)



# ─────────────────────────────────────────────────────────────────────────────
# SHARED HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def get_pack_by_id(pack_id):
    pack_id = getattr(settings, "LEGACY_PACK_IDS", {}).get(pack_id, pack_id)
    for pack in settings.CREDIT_PACKS:
        if pack["id"] == pack_id:
            return pack
    return None


def _get_user_profile(user):
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return profile


def _send_resend_email(to: str, subject: str, html: str):
    """Send an HTML email from support@realfaceai.app (settings.DEFAULT_FROM_EMAIL).

    Kept under its old name so existing callers keep working; it no longer
    uses Resend, only the SMTP mailbox configured in settings.py.
    """
    from django.core.mail import EmailMultiAlternatives

    try:
        msg = EmailMultiAlternatives(
            subject=subject,
            body="This email needs an HTML-capable mail client.",
            from_email=settings.DEFAULT_FROM_EMAIL,
            to=[to],
            reply_to=[settings.SUPPORT_EMAIL],
        )
        msg.attach_alternative(html, "text/html")
        msg.send(fail_silently=False)
        logger.info(f"Email sent to {to}: {subject}")
        return True
    except Exception as e:
        logger.error(f"Email to {to} failed: {e}")
        return False


def _send_resend_email_to_many(recipients: list, subject: str, html: str):
    """Send an email to multiple recipients from the support mailbox."""
    for addr in recipients:
        _send_resend_email(addr, subject, html)


def _run_in_background(fn, *args, **kwargs):
    """Fire-and-forget: run fn on a daemon thread so the HTTP response never waits on it."""
    def runner():
        close_old_connections()
        try:
            fn(*args, **kwargs)
        except Exception:
            logger.exception("Background task failed")
        finally:
            connection.close()

    threading.Thread(target=runner, daemon=True).start()


def _pick_wallet(currency):
    """Random active wallet for a network, as {'address','label','network'}."""
    wallets = list(
        CryptoWallet.objects.filter(is_active=True, network=currency)
        .values('address', 'label', 'network')
    )
    if wallets:
        return random.choice(wallets)
    return {'address': '', 'label': currency.upper(), 'network': currency}


def _ensure_wallet(payment):
    """Payments created before wallet_address existed get one assigned (once)."""
    if payment.wallet_address:
        return
    chosen = _pick_wallet(payment.currency)
    if chosen['address']:
        payment.wallet_address = chosen['address']
        payment.wallet_label = chosen['label'] or payment.currency.upper()
        payment.save(update_fields=['wallet_address', 'wallet_label'])


def _instructions(payment, **extra):
    """The response body the app uses to render the 'Payment Pending' dialog."""
    data = {
        "payment_id":     payment.payment_id,
        "status":         payment.status,
        "amount_usd":     str(payment.amount_usd),
        "credits":        payment.credits_to_add,
        "pack_id":        payment.pack_id,
        "pack_label":     payment.pack_label,
        "currency":       payment.currency,
        "gateway":        payment.gateway,
        "wallet_address": payment.wallet_address,
        "wallet_label":   payment.wallet_label or payment.currency.upper(),
        "wallet_network": payment.currency,
        "created_at":     payment.created_at,
        "confirmed_at":   payment.confirmed_at,
        "proof_count":    payment.proofs.count(),
        "message": (
            "Your payment request has been received and is pending confirmation. "
            "Please send the exact amount to the provided address. "
            "You will receive an email once your payment is confirmed."
        ),
    }
    data.update(extra)
    return data


def _credit_user_atomic(payment):
    """
    Atomically confirm a payment and add credits to the user.
    Returns (success: bool, new_balance: float)
    """
    with transaction.atomic():
        locked = CryptoPayment.objects.select_for_update().get(pk=payment.pk)

        if locked.status == CryptoPayment.STATUS_CONFIRMED:
            logger.info(f"Payment {payment.pk} already confirmed — skipping double credit")
            profile = _get_user_profile(locked.user)
            return False, float(profile.credits)

        locked.status       = CryptoPayment.STATUS_CONFIRMED
        locked.confirmed_at = timezone.now()
        locked.save(update_fields=[
            "status", "confirmed_at",
        ])

        profile     = _get_user_profile(locked.user)
        new_balance = profile.add_credits(locked.credits_to_add)
        profile.plan = locked.pack_id
        profile.save(update_fields=["plan", "credits"])

        def send_notifications():
            try:
                # ── User confirmation email ──────────────────────────────────
                # user_html = f"""
                # <div style="font-family:sans-serif;max-width:560px;margin:auto;padding:24px;background:#fff;border-radius:8px;">
                #   <h2 style="color:#4f46e5;margin-bottom:4px;">Payment Confirmed ✓</h2>
                #   <p style="color:#374151;">Hi {locked.user.email},</p>
                #   <p style="color:#374151;">Your payment has been confirmed and <strong>{locked.credits_to_add} credits</strong> have been added to your account.</p>
                #   <table style="border-collapse:collapse;width:100%;margin:16px 0;font-size:14px;">
                #     <tr style="background:#f9fafb;">
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#6b7280;font-weight:600;">Pack</td>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#111827;">{locked.pack_label}</td>
                #     </tr>
                #     <tr>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#6b7280;font-weight:600;">Credits Added</td>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#111827;">{locked.credits_to_add:,}</td>
                #     </tr>
                #     <tr style="background:#f9fafb;">
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#6b7280;font-weight:600;">Amount Paid</td>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#111827;">${locked.amount_usd}</td>
                #     </tr>
                #     <tr>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#6b7280;font-weight:600;">New Balance</td>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#16a34a;font-weight:600;">{float(new_balance):,.0f} credits</td>
                #     </tr>
                #   </table>
                #   <p style="color:#6b7280;font-size:13px;">Thank you for your purchase! Open the app to start using your credits.</p>
                # </div>
                # """
                # _send_resend_email(
                #     locked.user.email,
                #     f"Payment Confirmed — {locked.credits_to_add:,} credits added to your account",
                #     user_html,
                # )

                # ── Admin notification ───────────────────────────────────────
                admin_emails = getattr(settings, "ADMIN_EMAILS", [settings.SUPPORT_EMAIL])
                if isinstance(admin_emails, str):
                    admin_emails = [admin_emails]

                admin_html = render_to_string("emails/admin_payment_confirmed.html", {
                    "site_url": getattr(settings, "SITE_URL", "https://realfaceai.app"),
                    "payment": locked,
                    "credits": f"{locked.credits_to_add:,}",
                    "rows": [
                        ("User", locked.user.email, ""),
                        ("Pack", f"{locked.pack_label} ({locked.credits_to_add:,} credits)", ""),
                        ("Amount", f"${locked.amount_usd}", "accent"),
                        ("Gateway", locked.gateway, ""),
                        ("Payment ID", locked.pk, "mono"),
                        ("New balance", f"{float(new_balance):,.0f} credits", ""),
                    ],
                })
                _send_resend_email_to_many(
                    admin_emails,
                    f"Payment Confirmed: {locked.pack_label} — {locked.user.email}",
                    admin_html,
                )

            except Exception as e:
                logger.error(f"Failed to send payment confirmation emails: {e}")

        transaction.on_commit(send_notifications)

    logger.info(
        f"Payment confirmed: gateway={locked.gateway} user={locked.user.email} "
        f"credits_added={locked.credits_to_add} new_balance={new_balance}"
    )
    return True, float(new_balance)




# ─────────────────────────────────────────────────────────────────────────────
# CREDIT PACKS LIST
# ─────────────────────────────────────────────────────────────────────────────

class CreditPacksView(APIView):
    """GET /api/v1/payments/packs/"""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response(settings.CREDIT_PACKS)


class WalletAddressesView(APIView):
    """
    GET /api/v1/payments/wallets/

    Returns one randomly selected active wallet address per network.
    If multiple wallets share the same network key, a different address
    may be returned on each call — spreading funds across wallets and
    making on-chain reconciliation easier.

    Response shape (same contract the Flutter app already expects):
    {
      "usdttrc20": {"address": "T...", "label": "USDT TRC20", "network": "usdttrc20"},
      "btc":       {"address": "1...", "label": "Bitcoin",    "network": "btc"},
      ...
    }
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        active_wallets = list(
            CryptoWallet.objects.filter(is_active=True)
            .values('network', 'label', 'address')
        )

        # Group wallets by network, then pick one at random per network
        grouped = {}
        for w in active_wallets:
            grouped.setdefault(w['network'], []).append(w)

        result = {}
        for network, wallets in grouped.items():
            chosen = random.choice(wallets)
            result[network] = {
                'address': chosen['address'],
                'label':   chosen['label'],
                'network': network,
            }

        return Response(result)



class CurrenciesView(APIView):
    """
    GET /api/v1/payments/currencies/

    Returns the crypto and fiat currency lists the Flutter app should display.
    Crypto currencies are derived from active CryptoWallet entries (deduplicated
    by network). Fiat currencies come from FiatCurrency records.

    Response:
    {
      "crypto": [
        {"id": "usdttrc20", "label": "USDT TRC20"},
        ...
      ],
      "fiat": [
        {"id": "NGN", "label": "NGN", "flag": "🇳🇬"},
        ...
      ]
    }
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        # Crypto: one entry per unique network (preserve insertion order)
        wallets = (
            CryptoWallet.objects.filter(is_active=True)
            .values('network', 'label')
            .order_by('network', 'id')
        )
        seen = set()
        crypto = []
        for w in wallets:
            if w['network'] not in seen:
                seen.add(w['network'])
                crypto.append({
                    'id':    w['network'],
                    'label': w['label'],
                })

        # Fiat: all active fiat currencies ordered by sort_order
        fiat = list(
            FiatCurrency.objects.filter(is_active=True)
            .values('currency_id', 'label', 'flag')
        )
        fiat_out = [
            {'id': f['currency_id'], 'label': f['label'], 'flag': f['flag']}
            for f in fiat
        ]

        return Response({'crypto': crypto, 'fiat': fiat_out})


# ─────────────────────────────────────────────────────────────────────────────
# PAYMENT HISTORY — paginated (now includes proof info per payment)
# ─────────────────────────────────────────────────────────────────────────────

class PaymentHistoryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        try:
            page = max(1, int(request.query_params.get("page", 1)))
            page_size = min(50, max(1, int(request.query_params.get("page_size", 10))))
        except (TypeError, ValueError):
            page, page_size = 1, 10
        offset = (page - 1) * page_size

        latest_proof = PaymentProof.objects.filter(payment=OuterRef("pk")).order_by("-submitted_at")

        qs = (
            CryptoPayment.objects.filter(user=request.user)
            .annotate(
                proof_count=Count("proofs", distinct=True),
                last_proof_at=Max("proofs__submitted_at"),
                last_proof_local=Subquery(latest_proof.values("local_image")[:1]),
                last_proof_cloud=Subquery(latest_proof.values("proof_image")[:1]),
            )
            .order_by("-created_at")
        )
        total = qs.count()
        rows = qs.values(
            "payment_id", "pack_id", "pack_label", "amount_usd",
            "credits_to_add", "currency", "gateway",
            "status", "payment_url", "created_at", "confirmed_at",
            "wallet_address", "wallet_label",
            "proof_count", "last_proof_at", "last_proof_local", "last_proof_cloud",
        )[offset: offset + page_size]

        results = []
        for r in rows:
            local = r.pop("last_proof_local")
            cloud = r.pop("last_proof_cloud")
            # False → the most recent proof never made it (old background-upload bug)
            r["last_proof_has_image"] = bool(local or cloud) if r["proof_count"] else None
            results.append(r)

        return Response({
            "results":     results,
            "count":       total,
            "total_pages": max(1, -(-total // page_size)),
            "page":        page,
            "page_size":   page_size,
        })


# ─────────────────────────────────────────────────────────────────────────────
# PAYMENT STATUS POLL (+ full instructions, so the app can reopen them)
# ─────────────────────────────────────────────────────────────────────────────

class PaymentStatusView(APIView):
    """GET /api/v1/auth/<payment_id>/status/"""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, payment_id):
        try:
            payment = CryptoPayment.objects.get(payment_id=payment_id, user=request.user)
        except CryptoPayment.DoesNotExist:
            return Response({"error": "Payment not found."}, status=404)

        if payment.status in (CryptoPayment.STATUS_WAITING, CryptoPayment.STATUS_CONFIRMING):
            _ensure_wallet(payment)

        return Response(_instructions(
            payment,
            credits_balance=float(_get_user_profile(request.user).credits),
        ))


# ─────────────────────────────────────────────────────────────────────────────
# MANUAL PAYMENT — admin confirms via Django admin action
# ─────────────────────────────────────────────────────────────────────────────

# A second "Continue" for the same pack + network within this window returns
# the payment that already exists instead of piling up duplicate pending rows.
REUSE_PENDING_WITHIN = timedelta(minutes=30)


class CreatePaymentView(APIView):
    """
    POST /api/v1/auth/payments/create/
    Body: { "pack_id": "popular", "currency": "usdttrc20" }

    Creates (or reuses) a PENDING payment and returns the instructions.
    Responds fast: the admin email is sent on a background thread.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        pack_id  = (request.data.get("pack_id") or "").strip()
        currency = (request.data.get("currency") or "").strip()

        pack = get_pack_by_id(pack_id)
        if not pack:
            return Response(
                {"error": f"Invalid pack_id '{pack_id}'."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not currency or not CryptoWallet.objects.filter(is_active=True, network=currency).exists():
            return Response(
                {"error": "That payment network isn't available right now. Please pick another one."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # ── Reuse a fresh, untouched pending payment for the same choice ──────
        recent = (
            CryptoPayment.objects.filter(
                user=request.user,
                pack_id=pack_id,
                currency=currency,
                status=CryptoPayment.STATUS_WAITING,
                created_at__gte=timezone.now() - REUSE_PENDING_WITHIN,
            )
            .annotate(n_proofs=Count("proofs"))
            .filter(n_proofs=0)
            .order_by("-created_at")
            .first()
        )
        if recent is not None:
            _ensure_wallet(recent)
            return Response(_instructions(recent, reused=True), status=status.HTTP_200_OK)

        chosen_wallet = _pick_wallet(currency)

        payment = CryptoPayment.objects.create(
            user           = request.user,
            pack_id        = pack_id,
            pack_label     = pack["label"],
            amount_usd     = Decimal(str(pack["price_usd"])),
            credits_to_add = pack["credits"],
            currency       = currency,
            gateway        = CryptoPayment.GATEWAY_CRYPTO,
            status         = CryptoPayment.STATUS_WAITING,
            payment_url    = "",
            wallet_address = chosen_wallet["address"],
            wallet_label   = chosen_wallet["label"] or currency.upper(),
        )

        user_email = request.user.email

        def _notify_admin():
            admin_emails = getattr(settings, "ADMIN_EMAILS", [settings.SUPPORT_EMAIL])
            if isinstance(admin_emails, str):
                admin_emails = [admin_emails]

            html = render_to_string("emails/admin_payment_pending.html", {
                "site_url": getattr(settings, "SITE_URL", "https://realfaceai.app"),
                "payment": payment,
                "pack": pack,
                "user_email": user_email,
                "admin_url": f"{getattr(settings, 'BASE_URL', '')}/admin/account/cryptopayment/?status__exact=waiting",
                "rows": [
                    ("User", user_email, ""),
                    ("Pack", f"{pack['label']} ({pack['credits']:,} credits)", ""),
                    ("Amount", f"${pack['price_usd']}", "accent"),
                    ("Currency", currency.upper(), ""),
                    ("Wallet", payment.wallet_address or "—", "mono"),
                    ("Payment ID", payment.payment_id, "mono"),
                ],
            })
            _send_resend_email_to_many(
                admin_emails,
                f"New Pending Payment {payment.payment_id}: {pack['label']} — {user_email}",
                html,
            )

        # Background thread — NOT transaction.on_commit (that runs inline here).
        _run_in_background(_notify_admin)

        return Response(_instructions(payment), status=status.HTTP_201_CREATED)