"""
api/middleware.py

Server-side enforcement of mandatory desktop updates.

Desktop builds >= 1.1.0 send two headers on every API request:

    X-App-Platform: windows | macos
    X-App-Version:  1.1.0

If that version is below the platform's minimum supported version (the newest
published release marked "mandatory"), the request is rejected with

    426 Upgrade Required
    { "update_required": true, "code": "update_required", "stop": true, ... }

The app reacts by showing its blocking update screen. `stop: true` makes any
running stream end on the next heartbeat — old builds already honour that key.

Without enforcement here a "mandatory" update would only be a polite request:
an outdated client could ignore the prompt and keep calling the API.

Settings
--------
APP_UPDATE_ENFORCE                    (default True)  master switch
APP_UPDATE_BLOCK_UNVERSIONED_CLIENTS  (default False) also reject API calls
    that carry no X-App-Version header. 1.0.x builds don't send it, so only
    turn this on once you want to cut those builds off entirely.
"""

from django.conf import settings
from django.http import JsonResponse

from .versioning import (
    build_version_payload,
    get_policy,
    normalize_platform,
    parse_version,
    update_required_message,
)


class AppVersionMiddleware:
    API_PREFIX = "/api/"

    # Always reachable, even by outdated builds — otherwise the app couldn't
    # find out what to update to, or recover from maintenance.
    EXEMPT_PREFIXES = (
        "/api/v1/app/",       # latest-version + health
        "/api/v1/health/",
        "/api/v1/payments/deposit/scan",  # cron endpoints (no app headers)
    )

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        blocked = self._check(request)
        if blocked is not None:
            return blocked
        return self.get_response(request)

    def _check(self, request):
        if not getattr(settings, "APP_UPDATE_ENFORCE", True):
            return None
        path = request.path
        if not path.startswith(self.API_PREFIX) or path.startswith(self.EXEMPT_PREFIXES):
            return None
        if request.method == "OPTIONS":
            return None

        raw_version = request.headers.get("X-App-Version")
        platform = normalize_platform(request.headers.get("X-App-Platform"))

        if not raw_version:
            if getattr(settings, "APP_UPDATE_BLOCK_UNVERSIONED_CLIENTS", False):
                return self._unversioned_response(platform)
            return None

        client = parse_version(raw_version)
        if client is None or platform is None:
            return None  # unknown client shape — don't lock anyone out on a typo

        policy = get_policy(platform)
        if not policy.is_forced(client):
            return None

        body = build_version_payload(platform, raw_version, policy)
        body.update({
            "update_required": True,
            "code": "update_required",
            "error": update_required_message(raw_version, policy),
            "stop": True,
        })
        return JsonResponse(body, status=426)

    @staticmethod
    def _unversioned_response(platform):
        body = {
            "update_required": True,
            "code": "update_required",
            "stop": True,
            "error": "This version of RealFaceAI is no longer supported. Please download the latest version.",
        }
        policy = get_policy(platform) if platform else None
        if policy and policy.latest:
            body.update(build_version_payload(platform, None, policy))
            body["force_update"] = True
            body["mandatory"] = True
        return JsonResponse(body, status=426)
