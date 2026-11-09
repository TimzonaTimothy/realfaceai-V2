
# Lightweight health-check endpoint — exempt from MaintenanceModeMiddleware
# so the Flutter app can detect when the server comes back up.
#
# GET /api/v1/health/
#   200  { "status": "ok" }                    — server is healthy
#   503  { "maintenance": true, ... }           — blocked by middleware (won't
#                                                  reach this view — middleware
#                                                  intercepts first, EXCEPT this
#                                                  path is in EXEMPT_PATHS)

from django.http import JsonResponse


def health_check(request):
    """
    Always returns 200 {"status": "ok"}.
    The middleware exempts /api/v1/health/ so this view is always reachable,
    even during maintenance. The Flutter MaintenanceScreen hits this endpoint
    periodically to detect recovery.
    """
    return JsonResponse({'status': 'ok'})