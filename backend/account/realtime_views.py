"""
realtime_views.py
=================

Endpoint for issuing Decart realtime streaming tokens.

  POST /api/v1/auth/realtime/token/
  Body: { "model": "decart-model-id" }

  Returns:
  {
    "token":             "<decart_stream_token>",
    "expires_at":        "2026-01-01T00:00:00Z",
    "credits_remaining": 123.45
  }

Credit cost: deducted BEFORE the token is issued.
Every call is recorded in UsageLog for the dashboard chart.

Add to urls.py:
  from .realtime_views import RealtimeTokenView
  path("realtime/token/", RealtimeTokenView.as_view(), name="realtime_token"),

Add to settings.py:
  _STREAM_PROVIDER_URL = "your-stream-provider-url"
  REALTIME_CREDIT_COST = 10  # credits charged per token issuance
"""

import logging
from decimal import Decimal

import requests as http_requests

from django.conf import settings
from django.utils import timezone

from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import UserProfile, UsageLog

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

# STREAM_TOKEN_ENDPOINT = getattr(settings, "STREAM_TOKEN_ENDPOINT", "")   # adjust if different

def _get_user_profile(user) -> UserProfile:
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return profile


STREAM_TOKEN_ENDPOINT = getattr(settings, "STREAM_TOKEN_ENDPOINT", "")
DECART_API_KEY = getattr(settings, "DECART_API_KEY", "")
REALTIME_CREDIT_COST = Decimal(str(getattr(settings, "REALTIME_CREDIT_COST", 10)))


def _issue_decart_token(model: str) -> dict:
    if not DECART_API_KEY:
        raise RuntimeError("DECART_API_KEY is not configured on the server.")
    if not STREAM_TOKEN_ENDPOINT:
        raise RuntimeError("STREAM_TOKEN_ENDPOINT is not configured on the server.")

    try:
        resp = http_requests.post(
            STREAM_TOKEN_ENDPOINT,
            headers={
                "Authorization": f"Bearer {DECART_API_KEY}",
                "Content-Type": "application/json",
            },
            json={"model": model},
            timeout=15,
        )
    except http_requests.RequestException as exc:
        raise RuntimeError(f"Network error reaching Decart API: {exc}") from exc

    if resp.status_code == 200:
        try:
            return resp.json()
        except ValueError as exc:
            raise RuntimeError("Decart API returned non-JSON response.") from exc

    try:
        detail = resp.json().get("error") or resp.json().get("detail") or resp.text
    except Exception:
        detail = resp.text or f"HTTP {resp.status_code}"

    raise RuntimeError(f"Decart API error ({resp.status_code}): {detail}")
# ─────────────────────────────────────────────────────────────────────────────
# VIEW
# ─────────────────────────────────────────────────────────────────────────────

class RealtimeTokenView(APIView):
    """
    POST /api/v1/auth/realtime/token/

    Issues a Decart realtime streaming token after deducting credits.

    Steps:
      1. Validate the `model` field.
      2. Check user has enough credits.
      3. Deduct credits atomically.
      4. Call Decart API to get the token.
      5. If Decart call fails, refund the credits.
      6. Log the usage.
      7. Return the token + remaining balance.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        model = request.data.get("model", "").strip()
        if not model:
            return Response(
                {"error": "model is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        profile = _get_user_profile(request.user)

        # ── 1. Credit check ──────────────────────────────────────────────────
        if not profile.has_credits(REALTIME_CREDIT_COST):
            return Response(
                {
                    "error": (
                        f"Insufficient credits. "
                        f"You need {REALTIME_CREDIT_COST} credits to start a stream. "
                        f"Your balance: {float(profile.credits):.2f}."
                    )
                },
                status=status.HTTP_402_PAYMENT_REQUIRED,
            )

        # ── 2. Deduct credits ────────────────────────────────────────────────
        try:
            profile.deduct_credits(REALTIME_CREDIT_COST)
        except ValueError as exc:
            return Response({"error": str(exc)}, status=status.HTTP_402_PAYMENT_REQUIRED)

        # ── 3. Issue Decart token (refund on failure) ────────────────────────
        try:
            decart_data = _issue_decart_token(model)
        except RuntimeError as exc:
            # Refund the credits — token was never used
            profile.add_credits(REALTIME_CREDIT_COST)
            logger.error(
                "Decart token issuance failed for %s / model=%s: %s",
                request.user.email, model, exc,
            )
            return Response(
                {"error": str(exc)},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        # ── 4. Log the usage ─────────────────────────────────────────────────
        try:
            UsageLog.objects.create(
                user         = request.user,
                endpoint     = UsageLog.ENDPOINT_REALTIME,
                model_used   = model,
                credits_used = REALTIME_CREDIT_COST,
                metadata     = {"model": model},
            )
        except Exception as log_exc:
            # Never let a logging failure kill the response
            logger.error("UsageLog write failed: %s", log_exc)

        # ── 5. Respond ───────────────────────────────────────────────────────
        # Re-fetch so balance is accurate after deduction
        profile.refresh_from_db()

        return Response(
            {
                "token":             decart_data.get("token") or decart_data.get("api_key", ""),
                "expires_at":        decart_data.get("expires_at", ""),
                "credits_remaining": float(profile.credits),
            },
            status=status.HTTP_200_OK,
        )