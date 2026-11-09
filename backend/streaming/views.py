"""
streaming/views.py

Realtime streaming only. The model the app streams with is decided HERE
(settings.STREAM_MODEL_ID, default "x2.1") and handed to the desktop app
in the token response, so the app never hard-codes a model name and a model
switch needs no app release.

The provider is Xmax. The permanent XMAX_API_KEY never leaves the server:
each session gets an Xmax *temporary* key (tk-…) whose credit limit is what
the user's balance can pay for, with one concurrent session.

    POST /api/v1/stream/token/          start a session (charges first 10 s)
    POST /api/v1/stream/heartbeat/      every 10 s while live
    POST /api/v1/stream/token/refresh/  the current session key (or a new one)
    GET  /api/v1/stream/models/         the active model (public)
"""

import base64
import binascii
import hashlib
import hmac
import logging
import time
import uuid
from decimal import Decimal
from email.utils import parsedate_to_datetime
from urllib.parse import quote

import requests as http_requests
from django.conf import settings
from django.core.cache import cache
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from account.models import UsageLog, UserProfile

log = logging.getLogger(__name__)

CREDITS_PER_SECOND    = Decimal("2")
HEARTBEAT_INTERVAL_S  = 10
CREDITS_PER_HEARTBEAT = CREDITS_PER_SECOND * HEARTBEAT_INTERVAL_S
TOKEN_REFRESH_INTERVAL_MS = 4 * 60 * 1000

# Xmax X2.0 / X2.1 bill 1 Xmax credit per second of realtime session.
XMAX_POINTS_PER_SECOND = 1
# Slack on top of the user's paid seconds so heartbeat timing never cuts a
# stream the user has paid for.
XMAX_POINTS_BUFFER = 30


def _get_profile(user):
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return profile


def stream_config() -> dict:
    """What the app needs to open a session with the active model."""
    return {
        "model":              settings.STREAM_MODEL_ID,
        "model_name":         settings.STREAM_MODEL_NAME,
        "prompt":             settings.STREAM_FACE_PROMPT,
        "enhance":            settings.STREAM_PROMPT_ENHANCE,
        "credits_per_second": float(CREDITS_PER_SECOND),
    }


# ── Xmax temporary keys ───────────────────────────────────────────────────────

class XmaxError(RuntimeError):
    pass


def _xmax(method, path, body=None):
    if not settings.XMAX_API_KEY:
        raise XmaxError("XMAX_API_KEY is not configured on the server.")
    try:
        resp = http_requests.request(
            method,
            settings.XMAX_API_BASE.rstrip("/") + path,
            headers={"X-Api-Key": settings.XMAX_API_KEY,
                     "Content-Type": "application/json"},
            json=body,
            timeout=15,
        )
    except http_requests.RequestException as exc:
        raise XmaxError(f"network error: {exc}") from exc
    try:
        payload = resp.json()
    except ValueError as exc:
        raise XmaxError(f"non-JSON response (HTTP {resp.status_code})") from exc
    if resp.status_code // 100 != 2 or not payload.get("success"):
        raise XmaxError(f"HTTP {resp.status_code}, code {payload.get('code')}: "
                        f"{payload.get('message') or 'unknown error'}")
    return payload.get("data") or {}


def _cache_key(user):
    return f"xmax_temp_key:{user.pk}"


def _deactivate_temp_key(user):
    """Best effort: kill the user's last temporary key (and its session)."""
    key = cache.get(_cache_key(user))
    if not key:
        return
    cache.delete(_cache_key(user))
    try:
        _xmax("PUT", f"/temporary-api-key/{key}/inactive")
    except XmaxError as exc:
        log.warning("Xmax: could not deactivate temporary key for %s: %s", user.pk, exc)


def _create_temp_key(user, profile) -> dict:
    """A temporary key that can spend at most what the user's balance covers."""
    paid_seconds = int(profile.credits / CREDITS_PER_SECOND)
    points = min(paid_seconds * XMAX_POINTS_PER_SECOND + XMAX_POINTS_BUFFER,
                 settings.XMAX_TEMP_KEY_MAX_POINTS)

    # One live key per user: a key left over from the previous session could
    # otherwise keep streaming outside the app, unbilled by the heartbeat.
    _deactivate_temp_key(user)

    data = _xmax("POST", "/temporary-api-key", {
        "expireSeconds":               settings.XMAX_TEMP_KEY_TTL_S,
        "pointsLimit":                 max(points, 1),
        "temporaryApiKeySessionLimit": 1,
    })
    key = data.get("temporaryApiKey")
    if not key:
        raise XmaxError("response has no temporaryApiKey")
    cache.set(_cache_key(user), key, settings.XMAX_TEMP_KEY_TTL_S)
    log.info("Xmax temporary key issued for user %s (%s…, %s points)", user.pk, key[:6], points)
    return {"api_key": key, "expires_at": data.get("expireTimestamp")}


# ── Reference face upload ─────────────────────────────────────────────────────
# The model takes the face as a URL in Xmax's COS bucket. Uploading it here
# instead of in the app: the server's clock is right (COS rejects signatures
# from clients whose clock is off — "Local time is too skewed"), it is done
# before the stream page loads, and the same face is uploaded only once.

MAX_FACE_BYTES = 10 * 1024 * 1024
FACE_URL_CACHE_S = 24 * 60 * 60

# Seconds to add to this machine's clock to match COS's, learned from a
# rejected request ("Request has expired" / "too skewed").
_cos_clock_offset = 0


def _cos_authorization(secret_id, secret_key, method, path, headers):
    """Tencent COS request signature (q-sign-algorithm=sha1)."""
    now = int(time.time()) + _cos_clock_offset
    key_time = f"{now - 60};{now + 600}"
    sign_key = hmac.new(secret_key.encode(), key_time.encode(), hashlib.sha1).hexdigest()
    signed = {k.lower(): v for k, v in headers.items()}
    header_list = ";".join(sorted(quote(k, safe="") for k in signed))
    header_str = "&".join(f"{quote(k, safe='')}={quote(str(signed[k]), safe='')}"
                          for k in sorted(signed))
    http_string = f"{method.lower()}\n{path}\n\n{header_str}\n"
    string_to_sign = f"sha1\n{key_time}\n{hashlib.sha1(http_string.encode()).hexdigest()}\n"
    signature = hmac.new(sign_key.encode(), string_to_sign.encode(), hashlib.sha1).hexdigest()
    return (f"q-sign-algorithm=sha1&q-ak={secret_id}&q-sign-time={key_time}"
            f"&q-key-time={key_time}&q-header-list={header_list}"
            f"&q-url-param-list=&q-signature={signature}")


def _clock_rejected(resp):
    """True if COS refused the signature's time; then adopts COS's clock."""
    global _cos_clock_offset
    if "RequestTimeTooSkewed" not in resp.text and "expired" not in resp.text:
        return False
    try:
        server_now = parsedate_to_datetime(resp.headers["Date"]).timestamp()
    except (KeyError, TypeError, ValueError):
        return False
    _cos_clock_offset = int(server_now - time.time())
    log.warning("COS clock offset %+d s — this server's clock is wrong", _cos_clock_offset)
    return True


def _upload_reference_face(user, face_b64):
    """Uploads the user's face to Xmax storage; returns its URL, or None so
    the app falls back to uploading it itself."""
    if not face_b64 or not isinstance(face_b64, str):
        return None
    try:
        data = base64.b64decode(face_b64.split(",", 1)[-1], validate=False)
    except (binascii.Error, ValueError):
        return None
    if not data or len(data) > MAX_FACE_BYTES:
        return None

    cache_key = f"xmax_face:{user.pk}:{hashlib.sha256(data).hexdigest()}"
    cached = cache.get(cache_key)
    if cached:
        return cached

    is_png = data.startswith(b"\x89PNG")
    content_type, ext = ("image/png", "png") if is_png else ("image/jpeg", "jpg")
    try:
        sts = _xmax("GET", "/cos/sts")
        creds = sts["credentials"]
        bucket, region, prefix = sts["bucket"], sts["region"], sts["prefix"]
        key = f"{prefix}{int(time.time() * 1000)}_{uuid.uuid4().hex}_face.{ext}"
        path = "/" + quote(key)
        host = f"{bucket}.cos.{region}.myqcloud.com"
        headers = {"Host": host, "Content-Type": content_type,
                   "Content-Length": str(len(data))}

        def put():
            auth = _cos_authorization(creds["accessKeyId"], creds["secretAccessKey"],
                                      "PUT", path, headers)
            return http_requests.put(
                f"https://{host}{path}", data=data, timeout=30,
                headers={**headers, "Authorization": auth,
                         "x-cos-security-token": creds["sessionToken"]},
            )

        resp = put()
        if resp.status_code == 403 and _clock_rejected(resp):
            resp = put()
    except (XmaxError, KeyError, TypeError, http_requests.RequestException) as exc:
        log.warning("Face upload failed for %s: %s", user.pk, exc)
        return None
    if resp.status_code != 200:
        log.warning("Face upload failed for %s: COS HTTP %s %s",
                    user.pk, resp.status_code, resp.text[:200])
        return None

    url = f"https://{host}{path}"
    cache.set(cache_key, url, FACE_URL_CACHE_S)
    return url


class RealtimeTokenView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user    = request.user
        profile = _get_profile(user)
        config  = stream_config()

        # Older app builds still send {"model": "lucy-latest"}. The server owns
        # the model choice now, so a requested model is ignored, not rejected.
        requested = request.data.get("model")
        if requested and requested != config["model"]:
            log.info("Stream token: client asked for %r, serving %r", requested, config["model"])

        if not profile.has_credits(CREDITS_PER_HEARTBEAT):
            return Response({
                "error": "Insufficient credits.",
                "required": float(CREDITS_PER_HEARTBEAT),
                "available": float(profile.credits),
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        try:
            token_data = _create_temp_key(user, profile)
        except XmaxError as e:
            log.error("Xmax temporary key failed for %s: %s", user.pk, e)
            return Response({"error": "Streaming service unavailable. Please try again shortly."},
                            status=503)

        profile.deduct_credits(CREDITS_PER_HEARTBEAT)

        UsageLog.objects.create(
            user=user,
            endpoint=UsageLog.ENDPOINT_REALTIME,
            model_used=config["model"],
            credits_used=CREDITS_PER_HEARTBEAT,
            metadata={"model": config["model"], "type": "session_start"},
        )

        profile.refresh_from_db()
        return Response({
            "token":                     token_data["api_key"],
            "expires_at":                token_data.get("expires_at"),
            "reference_url":             _upload_reference_face(user, request.data.get("face_image")),
            **config,
            "credits_remaining":         float(profile.credits),
            "heartbeat_interval_s":      HEARTBEAT_INTERVAL_S,
            "token_refresh_interval_ms": TOKEN_REFRESH_INTERVAL_MS,
        })


class StreamHeartbeatView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        profile = _get_profile(request.user)

        if not profile.has_credits(CREDITS_PER_HEARTBEAT):
            if float(profile.credits) > 0:
                try:
                    profile.deduct_credits(profile.credits)
                except Exception:
                    pass
            # End the provider session too, even if the client ignores stop.
            _deactivate_temp_key(request.user)
            return Response({"stop": True, "credits_remaining": 0,
                             "error": "Out of credits."}, status=402)

        profile.deduct_credits(CREDITS_PER_HEARTBEAT)
        UsageLog.objects.create(
            user=request.user, endpoint=UsageLog.ENDPOINT_REALTIME,
            model_used="heartbeat", credits_used=CREDITS_PER_HEARTBEAT,
            metadata={"type": "heartbeat", "model": settings.STREAM_MODEL_ID},
        )
        return Response({"stop": False, "credits_remaining": float(profile.credits)})


class RealtimeTokenRefreshView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        profile = _get_profile(request.user)
        if float(profile.credits) <= 0:
            return Response({"error": "No credits.", "stop": True}, status=402)
        # An Xmax session is bound to the key it started with, so a live
        # stream keeps its key; a new one is only issued when there is none.
        key = cache.get(_cache_key(request.user))
        expires_at = None
        if not key:
            try:
                token_data = _create_temp_key(request.user, profile)
            except XmaxError as e:
                log.error("Xmax temporary key refresh failed for %s: %s", request.user.pk, e)
                return Response({"error": "Token refresh failed."}, status=503)
            key, expires_at = token_data["api_key"], token_data.get("expires_at")
        return Response({
            "token":             key,
            "expires_at":        expires_at,
            "model":             settings.STREAM_MODEL_ID,
            "credits_remaining": float(profile.credits),
        })


class AvailableModelsView(APIView):
    """Public: the single model streaming currently uses."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        config = stream_config()
        return Response({
            "realtime": [{
                "id":              config["model"],
                "name":            config["model_name"],
                "cost_per_second": config["credits_per_second"],
            }],
        })
