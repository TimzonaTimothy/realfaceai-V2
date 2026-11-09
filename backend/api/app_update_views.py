"""
api/app_update_views.py

GET /api/v1/app/latest-version/?platform=<windows|macos>&current_version=<x.y.z>

Release data now lives in the database (Django admin → App releases) instead
of being hard-coded here, so shipping or forcing an update no longer needs a
deploy. See api/versioning.py for how "latest" and "minimum supported" are
derived.

The client may send its version either as ?current_version= or via the
X-App-Version header (which every request from builds >= 1.1.0 carries).
"""

from django.http import JsonResponse
from django.views.decorators.cache import never_cache
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET

from .versioning import (
    SUPPORTED_PLATFORMS,
    build_version_payload,
    get_policy,
    normalize_platform,
)


@require_GET
@csrf_exempt
@never_cache
def latest_version(request):
    raw_platform = (
        request.GET.get("platform")
        or request.headers.get("X-App-Platform")
        or "windows"  # 1.0.x builds always send ?platform=, keep old default
    )
    platform = normalize_platform(raw_platform)
    if platform is None:
        return JsonResponse(
            {
                "error": (
                    f"Unsupported platform '{raw_platform}'. "
                    f"Use one of: {', '.join(sorted(SUPPORTED_PLATFORMS))}"
                )
            },
            status=400,
        )

    client_version = (
        request.GET.get("current_version")
        or request.headers.get("X-App-Version")
        or None
    )

    policy = get_policy(platform)
    if policy.latest is None:
        return JsonResponse(
            {"error": f"No release has been published for {platform} yet.", "platform": platform},
            status=404,
        )

    return JsonResponse(build_version_payload(platform, client_version, policy))
