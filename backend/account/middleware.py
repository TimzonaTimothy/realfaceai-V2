from django.conf import settings
from django.http import JsonResponse

class MaintenanceModeMiddleware:
    EXEMPT_PATHS = [
        '/admin/',
        # '/api/v1/auth/admin-login/',
    ]

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if getattr(settings, 'MAINTENANCE_MODE', False):
            # Allow admin paths through
            if not any(request.path.startswith(p) for p in self.EXEMPT_PATHS):
                return JsonResponse({
                    'maintenance': True,
                    'message': settings.MAINTENANCE_MESSAGE,
                    'retry_after': 3600,  # hint to app: check again in 1 hour
                }, status=503)
        return self.get_response(request)