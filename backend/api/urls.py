from django.urls import path
from .app_update_views import latest_version
from .health_views import health_check

urlpatterns = [
    
    # Desktop app auto-update  (registered under "api/v1/app/" in deep/urls.py)
    path("latest-version/", latest_version, name="app_latest_version"),

    # Health check — exempt from maintenance middleware, always reachable.
    # Registered under "api/v1/app/" AND directly under "api/v1/health/"
    # (see deep/urls.py for the second registration).
    path('health/', health_check, name='health_check'),
]
 