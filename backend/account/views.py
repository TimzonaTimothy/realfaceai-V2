from django.shortcuts import render, redirect,get_object_or_404
from django.core.exceptions import ObjectDoesNotExist
from .models import *
from django.contrib.auth import login
from django.contrib import auth
from django.urls import reverse_lazy,reverse
from django.contrib.auth.decorators import login_required
from django.contrib.auth import logout
from django.http import HttpResponseRedirect, HttpResponse,JsonResponse,HttpRequest
from django.contrib import messages
from django.contrib.sites.shortcuts import get_current_site
from django.template.loader import render_to_string
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from django.utils.encoding import force_bytes
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import EmailMessage
import hmac, hashlib, json
from django.views.decorators.csrf import csrf_exempt
from django.conf import settings
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.decorators import api_view, permission_classes, parser_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from django.shortcuts import get_object_or_404
import threading
import time
# Create your views here.

def download_app_view(request):
    return render(request, 'download_app.html')


def serve_download_file(request):
    """
    Serves the installer binary from downloads/mac/ or downloads/windows/.
    URL: /download/file/?platform=mac  or  /download/file/?platform=windows
 
    Place your installer files here:
      downloads/mac/     → e.g. RealFaceAI-1.0.0.dmg
      downloads/windows/ → e.g. RealFaceAI-Setup-1.0.0.exe
    """
    import os
    import mimetypes
    from django.conf import settings
    from django.http import FileResponse, Http404
 
    platform = request.GET.get('platform', '').lower()
 
    # Map platform to folder and expected extension
    PLATFORM_MAP = {
        'mac':     ('mac',     ('.dmg', '.pkg', '.zip')),
        'macos':   ('mac',     ('.dmg', '.pkg', '.zip')),
        'windows': ('windows', ('.exe', '.msi', '.zip')),
        'win':     ('windows', ('.exe', '.msi', '.zip')),
    }
 
    if platform not in PLATFORM_MAP:
        from django.http import HttpResponseBadRequest
        return HttpResponseBadRequest("Unknown platform. Use ?platform=mac or ?platform=windows")
 
    folder_name, valid_exts = PLATFORM_MAP[platform]
    dl_dir = os.path.join(settings.BASE_DIR, 'downloads', folder_name)
 
    if not os.path.isdir(dl_dir):
        from django.contrib import messages as _msg
        _msg.error(request, f"The {folder_name} installer folder is not configured yet. Please contact support.")
        return redirect("/download/")
 
    # Pick the first matching file
    installer_file = None
    for fname in sorted(os.listdir(dl_dir)):
        if fname.lower().endswith(valid_exts):
            installer_file = fname
            break
 
    if not installer_file:
        from django.contrib import messages as _msg
        platform_label = "macOS" if folder_name == "mac" else "Windows"
        _msg.error(request, f"The {platform_label} installer is not available yet — check back soon.")
        return redirect("/download/")
 
    file_path = os.path.join(dl_dir, installer_file)
    mime_type, _ = mimetypes.guess_type(file_path)
    mime_type = mime_type or 'application/octet-stream'
 
    response = FileResponse(open(file_path, 'rb'), content_type=mime_type)
    response['Content-Disposition'] = f'attachment; filename="{installer_file}"'
    return response


# api 
from django.db.models import Sum
from django.db.models.functions import TruncDate
from django.utils import timezone
from datetime import timedelta
 
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
 
from .models import Account, UserProfile, UsageLog, AccountStatusLog
from .serializers import RegisterSerializer, UserProfileSerializer, UsageLogSerializer
from .account_status import (
    CODE_SUSPENDED,
    SUSPENDED,
    AccountSuspended,
    StatusChangeError,
    change_account_status,
    effective_status,
    restriction_body,
    status_payload,
)


def _get_user_profile(user):
    """Get or create a UserProfile for credit operations."""
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return profile



class RegisterView(generics.CreateAPIView):
    """
    POST /api/v1/auth/register/
 
    Create a new user account.
    Returns JWT tokens so the user is logged in immediately.
    """
    permission_classes = [permissions.AllowAny]
    serializer_class = RegisterSerializer
 
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        # Ensure UserProfile exists (serializer already creates it, but safe)
        UserProfile.objects.get_or_create(user=user)
 
        # Issue tokens immediately after registration
        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "user": UserProfileSerializer(user).data,
                "access": str(refresh.access_token),
                "refresh": str(refresh),
            },
            status=status.HTTP_201_CREATED,
        )
 
 
# ─────────────────────────────────────────────────────────────────────────────
# LOGIN
# ─────────────────────────────────────────────────────────────────────────────
 
class LoginView(APIView):
    """
    POST /api/v1/auth/login/
    Body: { "email": "...", "password": "..." }
 
    Returns JWT access + refresh tokens.
    """
    permission_classes = [permissions.AllowAny]
 
    def post(self, request):
        email = request.data.get("email", "").strip().lower()
        password = request.data.get("password", "")
 
        if not email or not password:
            return Response(
                {"error": "Email and password are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
 
        try:
            user = Account.objects.get(email=email)
        except Account.DoesNotExist:
            return Response(
                {"error": "Invalid email or password."},
                status=status.HTTP_401_UNAUTHORIZED,
            )
 
        if not user.check_password(password):
            return Response(
                {"error": "Invalid email or password."},
                status=status.HTTP_401_UNAUTHORIZED,
            )
 
        if not user.is_active:
            return Response(
                {"error": "Account is deactivated. Contact support."},
                status=status.HTTP_403_FORBIDDEN,
            )

        # Suspension is only revealed after the password checks out, so this
        # can't be used to probe which emails have accounts. Frozen accounts
        # may still sign in (read-only); the app reads `user.account_status`.
        if effective_status(user) == SUSPENDED:
            return Response(
                restriction_body(user, CODE_SUSPENDED),
                status=status.HTTP_403_FORBIDDEN,
            )

        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "user": UserProfileSerializer(user).data,
                "access": str(refresh.access_token),
                "refresh": str(refresh),
            }
        )
 
 
# ─────────────────────────────────────────────────────────────────────────────
# PROFILE
# ─────────────────────────────────────────────────────────────────────────────
 
class MeView(generics.RetrieveAPIView):
    """
    GET /api/v1/auth/me/
 
    Returns the current user's profile and credit balance.
    Flutter polls this to keep the balance display up to date.
    """
    serializer_class = UserProfileSerializer
    permission_classes = [permissions.IsAuthenticated]
 
    def get_object(self):
        return self.request.user
 
 
# ─────────────────────────────────────────────────────────────────────────────
# DASHBOARD STATS (replaces WebSocket — Flutter polls this)
# ─────────────────────────────────────────────────────────────────────────────
 
class DashboardStatsView(APIView):
    """
    GET /api/v1/auth/dashboard/?days=30
 
    Returns everything the Flutter dashboard needs in one call:
    - Current credit balance
    - Total credits used in the period
    - Daily usage breakdown (for the chart)
    - Recent activity log
 
    Flutter calls this every 4–5 seconds to stay up to date.
    No WebSockets needed.
    """
    permission_classes = [permissions.IsAuthenticated]
 
    def get(self, request):
        user = request.user
        days = int(request.query_params.get("days", 30))
        since = timezone.now() - timedelta(days=days)
 
        logs = UsageLog.objects.filter(user=user, timestamp__gte=since)
 
        # Total credits used in period
        total_used = logs.aggregate(t=Sum("credits_used"))["t"] or 0
 
        # Daily breakdown for chart — [{date, credits_used}]
        daily = (
            logs
            .annotate(date=TruncDate("timestamp"))
            .values("date")
            .annotate(credits=Sum("credits_used"))
            .order_by("date")
        )
 
        activity_page      = max(1, int(request.query_params.get("activity_page", 1)))
        activity_page_size = min(50, max(1, int(request.query_params.get("activity_page_size", 8))))
        activity_offset    = (activity_page - 1) * activity_page_size
        activity_qs        = logs.order_by("-timestamp")
        activity_total     = activity_qs.count()
        recent             = activity_qs[activity_offset: activity_offset + activity_page_size]
        profile = _get_user_profile(user)
        return Response({
            "credits_remaining": float(profile.credits),
            "plan": profile.plan,
            "total_credits_used": float(total_used),
            "period_days": days,
            "daily_usage": [{"date": str(r["date"]), "credits": float(r["credits"])} for r in daily],
            "recent_activity": UsageLogSerializer(recent, many=True).data,
            "activity_total": activity_total,
            "activity_total_pages": max(1, -(-activity_total // activity_page_size)),
            "activity_page": activity_page,
            "activity_page_size": activity_page_size,
        })
 
 
# ─────────────────────────────────────────────────────────────────────────────
# POLLING ENDPOINT (replaces WebSocket push)
# ─────────────────────────────────────────────────────────────────────────────
 
from rest_framework.throttling import UserRateThrottle

class PollingRateThrottle(UserRateThrottle):
    scope = "polling"

class PollStatusView(APIView):
    """
    GET /api/v1/auth/poll/
 
    Lightweight endpoint Flutter calls every 4 seconds.
    Returns: current credit balance + latest activity.
 
    This replaces Django Channels WebSocket push.
    Works perfectly on cPanel shared hosting.
    """
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes    = [PollingRateThrottle]
 
    def get(self, request):
        user = request.user
        profile = _get_user_profile(user)
 
        latest = (
            UsageLog.objects
            .filter(user=user)
            .order_by("-timestamp")
            .values("endpoint", "credits_used", "timestamp", "model_used")
            .first()
        )
 
        return Response({
            "credits": float(profile.credits),
            "latest_activity": latest,
            # Lets the app pick up a freeze / unfreeze within one poll cycle.
            # (A suspension never reaches here — authentication returns 403.)
            "account_status": status_payload(user),
        })
 
 
# ─────────────────────────────────────────────────────────────────────────────
# USAGE LOG LIST
# ─────────────────────────────────────────────────────────────────────────────
 
class UsageLogListView(generics.ListAPIView):
    """
    GET /api/v1/auth/usage/
 
    Full paginated usage history.
    """
    serializer_class = UsageLogSerializer
    permission_classes = [permissions.IsAuthenticated]
 
    def get_queryset(self):
        return UsageLog.objects.filter(user=self.request.user).order_by("-timestamp")












from django.core.mail import EmailMultiAlternatives


# ─────────────────────────────────────────────────────────────────────────────
# EMAIL HELPER: every email goes out from support@realfaceai.app
# (settings.EMAIL_HOST_USER / DEFAULT_FROM_EMAIL), over the SMTP server
# configured in settings.py. No other mailbox or email provider is used.
# ─────────────────────────────────────────────────────────────────────────────

def _send_desktop_email(to_email, subject: str, html_body: str) -> None:
    """Send an HTML email from the RealFaceAI support mailbox.

    `to_email` may be one address or a list of addresses.
    Raises on failure so callers can decide how to report it.
    """
    recipients = [to_email] if isinstance(to_email, str) else list(to_email)
    msg = EmailMultiAlternatives(
        subject=subject,
        body='This email needs an HTML-capable mail client.',
        from_email=settings.DEFAULT_FROM_EMAIL,
        to=recipients,
        reply_to=[settings.SUPPORT_EMAIL],
    )
    msg.attach_alternative(html_body, 'text/html')
    msg.send(fail_silently=False)


def _notify_admin_new_proof(payment, proof):
    """Email the admin inbox when a payment proof is submitted."""
    admin_url = f"{settings.SITE_URL}/admin/payments/paymentproof/{proof.id}/change/"

    _send_desktop_email(
        to_email=settings.ADMIN_EMAIL,
        subject=f"[Action Required] New Payment Proof — #{payment.id}",
        html_body=render_to_string('emails/admin_payment_proof.html', {
            'site_url': settings.SITE_URL,
            'payment': payment,
            'proof': proof,
            'admin_url': admin_url,
            'rows': [
                ('Payment ID', f"#{payment.id}", ''),
                ('User', payment.user.email, ''),
                ('Amount', f"${payment.amount_usd}", 'accent'),
                ('Currency', payment.currency.upper(), ''),
                ('TX hash', proof.tx_hash, 'mono'),
                ('Notes', proof.notes, ''),
            ],
        }),
    )


def _finish_proof_upload(payment_id, proof_id, image_name, image_bytes):
    """
    Runs on a background thread, OFF the request/response cycle.

    This is where the slow, network-bound work happens: uploading the image
    to Cloudinary and emailing the admin from the support mailbox. Neither of those should
    ever hold up the HTTP response — on shared hosting in particular, a
    request that sits waiting on two outbound network calls is exactly what
    gets killed by Apache/LiteSpeed/Passenger before it can respond.

    Each submission now gets its own PaymentProof row (see submit_payment_proof
    below), so unlike the old one-row-per-payment design, there's no chance
    of two submissions racing to overwrite the same row/image — this thread
    only ever touches the one row it was handed.
    """
    from django.core.files.base import ContentFile

    try:
        proof = PaymentProof.objects.select_related('payment', 'payment__user').get(id=proof_id)
    except PaymentProof.DoesNotExist:
        return

    # Cloudinary upload can fail transiently (network blip between this
    # server and Cloudinary) — retry a few times with backoff before giving
    # up, instead of marking the proof failed on the first hiccup.
    uploaded_ok = False
    for attempt in range(3):
        try:
            proof.proof_image.save(image_name, ContentFile(image_bytes), save=False)
            uploaded_ok = True
            break
        except Exception:
            time.sleep(2 ** attempt)  # 1s, 2s, 4s

    if not uploaded_ok:
        PaymentProof.objects.filter(id=proof_id).update(upload_status=PaymentProof.STATUS_FAILED)
        return

    PaymentProof.objects.filter(id=proof_id).update(
        proof_image=proof.proof_image.name,
        upload_status=PaymentProof.STATUS_UPLOADED,
    )

    try:
        _notify_admin_new_proof(proof.payment, proof)
    except Exception:
        pass  # never let email failure affect the stored proof


_PROOF_ACCEPTED_DETAIL = (
    'Proof received and is being processed. It will appear on your payment shortly.'
)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def submit_payment_proof(request, payment_id):
    payment = get_object_or_404(CryptoPayment, payment_id=payment_id, user=request.user)

    if payment.status == 'confirmed':
        return Response({'error': 'Payment already confirmed.'}, status=400)

    # ── Idempotency ──────────────────────────────────────────────────────
    # The client sends one key per submission attempt and reuses it on every
    # retry of that same attempt (e.g. after a dropped connection). If we've
    # already recorded this exact key for this payment, the original request
    # got through even though the client never saw the response — so we just
    # re-acknowledge it rather than creating a second row, re-uploading to
    # Cloudinary, and re-emailing the admin.
    idempotency_key = (request.headers.get('Idempotency-Key') or '').strip()
    if idempotency_key:
        existing = PaymentProof.objects.filter(
            payment=payment, idempotency_key=idempotency_key,
        ).first()
        if existing is not None:
            return Response({'detail': _PROOF_ACCEPTED_DETAIL}, status=202)

    image = request.FILES.get('proof_image')
    if not image:
        return Response({'error': 'proof_image is required.'}, status=400)

    # Read the upload into memory NOW, on the request thread. This is a
    # local read (client -> this server), which is fast and not the part
    # that was timing out — the slow leg is this server -> Cloudinary.
    image_name = image.name
    image_bytes = image.read()

    # A genuinely new submission (new idempotency key, or none at all) gets
    # its OWN row — resubmitting no longer overwrites the previous proof, it
    # adds to the history, all traceable back to this same payment_id via
    # payment.proofs.all().
    proof = PaymentProof.objects.create(
        payment=payment,
        tx_hash=request.data.get('tx_hash', ''),
        notes=request.data.get('notes', ''),
        upload_status=PaymentProof.STATUS_PENDING,
        idempotency_key=idempotency_key or None,
    )

    # Hand the slow part (Cloudinary upload + admin email) to a background
    # thread and respond right away. No task queue/worker needed for this —
    # it's just a thread in the same process, which is fine on shared
    # hosting since we're not waiting on it.
    threading.Thread(
        target=_finish_proof_upload,
        args=(payment.id, proof.id, image_name, image_bytes),
        daemon=True,
    ).start()

    return Response({'detail': _PROOF_ACCEPTED_DETAIL}, status=202)





# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP — FORGOT PASSWORD  (sends 6-digit OTP, no URL exposed)
# POST /api/v1/auth/desktop/forgot-password/
# Body: { "email": "user@example.com" }
# ─────────────────────────────────────────────────────────────────────────────

from .models import PasswordResetOTP

class DesktopForgotPasswordView(APIView):
    """
    Generates a 6-digit OTP code and emails it to the user.
    The user enters the code in the desktop app — no browser link is ever
    shown, so the backend domain stays completely hidden.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        email = request.data.get('email', '').strip().lower()
        if not email:
            return Response(
                {'error': 'Email is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            user = Account.objects.get(email=email)
        except Account.DoesNotExist:
            # Return success to avoid user-enumeration attacks
            return Response(
                {'detail': 'If an account with that email exists, a reset code has been sent.'},
                status=status.HTTP_200_OK,
            )

        otp = PasswordResetOTP.create_for_user(user)

        html_body = render_to_string('emails/password_reset_code.html', {
            'site_url': settings.SITE_URL,
            'email': user.email,
            'code': otp.code,
        })

        try:
            _send_desktop_email(
                to_email=email,
                subject='Your RealFaceAI password reset code',
                html_body=html_body,
            )
        except Exception:
            return Response(
                {'error': 'Failed to send email. Please try again later.'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {'detail': 'If an account with that email exists, a reset code has been sent.'},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP — VERIFY OTP & RESET PASSWORD
# POST /api/v1/auth/desktop/verify-otp/
# Body: { "email": "...", "code": "123456", "new_password": "...", "confirm_password": "..." }
# ─────────────────────────────────────────────────────────────────────────────

class DesktopVerifyOTPView(APIView):
    """
    Accepts the 6-digit OTP code + new password.
    Verifies the code, resets the password, and returns success.
    No browser, no links, no domain leakage.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        email            = request.data.get('email', '').strip().lower()
        code             = request.data.get('code', '').strip()
        new_password     = request.data.get('new_password', '')
        confirm_password = request.data.get('confirm_password', '')

        if not email or not code or not new_password or not confirm_password:
            return Response(
                {'error': 'All fields are required (email, code, new_password, confirm_password).'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if new_password != confirm_password:
            return Response(
                {'error': 'Passwords do not match.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if len(new_password) < 8:
            return Response(
                {'error': 'Password must be at least 8 characters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            user = Account.objects.get(email=email)
        except Account.DoesNotExist:
            return Response(
                {'error': 'Invalid email or code.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Find the latest unused OTP for this user
        otp = PasswordResetOTP.objects.filter(
            user=user, is_used=False
        ).order_by('-created_at').first()

        if not otp or not otp.is_valid():
            return Response(
                {'error': 'Code has expired or is invalid. Please request a new one.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Increment attempts
        otp.attempts += 1
        otp.save(update_fields=['attempts'])

        if otp.code != code:
            remaining = 3 - otp.attempts
            if remaining <= 0:
                return Response(
                    {'error': 'Too many incorrect attempts. Please request a new code.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response(
                {'error': f'Incorrect code. {remaining} attempt(s) remaining.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Code is correct — reset the password
        user.set_password(new_password)
        user.save()

        # Mark OTP as used
        otp.is_used = True
        otp.save(update_fields=['is_used'])

        return Response(
            {'detail': 'Password reset successfully. You can now log in with your new password.'},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP — CHANGE PASSWORD  (authenticated)
# POST /api/v1/auth/desktop/change-password/
# Body: { "current_password": "...", "new_password": "...", "confirm_password": "..." }
# ─────────────────────────────────────────────────────────────────────────────

class DesktopChangePasswordView(APIView):
    """
    Allows an authenticated desktop user to change their password.
    Verifies the current password, validates the new one, updates it.
    The user stays logged in — their JWT tokens remain valid.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user             = request.user
        current_password = request.data.get('current_password', '')
        new_password     = request.data.get('new_password', '')
        confirm_password = request.data.get('confirm_password', '')

        # ── Validate inputs ──────────────────────────────────────────────────
        if not current_password or not new_password or not confirm_password:
            return Response(
                {'error': 'All fields are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not user.check_password(current_password):
            return Response(
                {'error': 'Current password is incorrect.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if new_password != confirm_password:
            return Response(
                {'error': 'New passwords do not match.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if len(new_password) < 8:
            return Response(
                {'error': 'New password must be at least 8 characters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if new_password == current_password:
            return Response(
                {'error': 'New password must differ from your current password.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # ── Apply change ─────────────────────────────────────────────────────
        user.set_password(new_password)
        user.save()

        return Response(
            {'detail': 'Password changed successfully.'},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────────────────────────────────────
# TOKEN REFRESH — refuses suspended accounts
# POST /api/v1/auth/refresh/   Body: { "refresh": "<token>" }
# ─────────────────────────────────────────────────────────────────────────────

from rest_framework_simplejwt.exceptions import AuthenticationFailed as JWTAuthenticationFailed
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings as jwt_settings
from rest_framework_simplejwt.views import TokenRefreshView


class AccountStatusTokenRefreshSerializer(TokenRefreshSerializer):
    """
    simplejwt's refresh doesn't look at the user at all, so a suspended (or
    deleted / deactivated) user could keep minting access tokens. Those tokens
    would still be refused by AccountStatusJWTAuthentication, but refusing
    here too gives the app a clear 403 at the point it tries to refresh.
    """

    def validate(self, attrs):
        refresh = self.token_class(attrs["refresh"])  # raises TokenError → 401
        user_id = refresh.payload.get(jwt_settings.USER_ID_CLAIM)
        user = Account.objects.filter(**{jwt_settings.USER_ID_FIELD: user_id}).first()
        if user is None or not user.is_active:
            raise JWTAuthenticationFailed("User not found or inactive.", code="user_inactive")
        if effective_status(user) == SUSPENDED:
            raise AccountSuspended(user)
        return super().validate(attrs)


class AccountStatusTokenRefreshView(TokenRefreshView):
    serializer_class = AccountStatusTokenRefreshSerializer


# ─────────────────────────────────────────────────────────────────────────────
# STAFF API — suspend / freeze / reactivate
#   GET  /api/v1/auth/admin/accounts/<id-or-email>/status/
#   POST /api/v1/auth/admin/accounts/<id-or-email>/status/
#        { "status": "active"|"frozen"|"suspended",
#          "reason": "shown to the user",          (optional)
#          "note": "internal",                     (optional)
#          "duration_hours": 72  | "expires_at": "2026-11-01T00:00:00Z",  (optional)
#          "notify": true }                        (optional, default true)
# Requires a staff (is_staff) account's JWT.
# ─────────────────────────────────────────────────────────────────────────────

from django.utils.dateparse import parse_datetime


def _find_account(identifier):
    if str(identifier).isdigit():
        return Account.objects.filter(pk=int(identifier)).first()
    return Account.objects.filter(email__iexact=str(identifier).strip()).first()


def _history(account, limit=50):
    rows = account.status_history.select_related("actor")[:limit]
    return [
        {
            "from_status": r.from_status,
            "to_status": r.to_status,
            "reason": r.reason,
            "note": r.note,
            "expires_at": r.expires_at.isoformat() if r.expires_at else None,
            "actor": r.actor.email if r.actor else None,
            "source": r.source,
            "created_at": r.created_at.isoformat(),
        }
        for r in rows
    ]


class AdminAccountStatusView(APIView):
    permission_classes = [permissions.IsAdminUser]

    def get(self, request, identifier):
        account = _find_account(identifier)
        if account is None:
            return Response({"error": "Account not found."}, status=status.HTTP_404_NOT_FOUND)
        effective_status(account)
        return Response({
            "id": account.pk,
            "email": account.email,
            "account_status": status_payload(account),
            "note": account.status_note,
            "changed_by": account.status_changed_by.email if account.status_changed_by else None,
            "history": _history(account),
        })

    def post(self, request, identifier):
        account = _find_account(identifier)
        if account is None:
            return Response({"error": "Account not found."}, status=status.HTTP_404_NOT_FOUND)

        actor = request.user
        if account.pk == actor.pk:
            return Response({"error": "You can't change your own account status."}, status=400)
        if (account.is_superuser or account.is_staff) and not actor.is_superuser:
            return Response({"error": "Only a superuser can restrict a staff account."}, status=403)

        new_status = str(request.data.get("status", "")).strip().lower()

        expires_at = None
        raw_expires = request.data.get("expires_at")
        raw_hours = request.data.get("duration_hours")
        if raw_expires:
            expires_at = parse_datetime(str(raw_expires))
            if expires_at is None:
                return Response({"error": "expires_at must be an ISO 8601 datetime."}, status=400)
            if timezone.is_naive(expires_at):
                expires_at = timezone.make_aware(expires_at, timezone.utc)
        elif raw_hours not in (None, ""):
            try:
                hours = float(raw_hours)
                if hours <= 0:
                    raise ValueError
            except (TypeError, ValueError):
                return Response({"error": "duration_hours must be a positive number."}, status=400)
            expires_at = timezone.now() + timedelta(hours=hours)

        notify = request.data.get("notify", True)
        if isinstance(notify, str):
            notify = notify.strip().lower() not in ("0", "false", "no")

        try:
            entry = change_account_status(
                account, new_status,
                reason=request.data.get("reason", ""),
                note=request.data.get("note", ""),
                expires_at=expires_at,
                actor=actor,
                source=AccountStatusLog.SOURCE_API,
                notify=bool(notify),
            )
        except StatusChangeError as e:
            return Response({"error": str(e)}, status=400)

        return Response({
            "changed": entry is not None,
            "id": account.pk,
            "email": account.email,
            "account_status": status_payload(account),
        })
