from django.urls import path
from .views import (
    RealtimeTokenView,
    RealtimeTokenRefreshView,
    StreamHeartbeatView,
    AvailableModelsView,
)

# Streaming only — the video / image generation endpoints were removed.
urlpatterns = [
    path("token/",          RealtimeTokenView.as_view(),        name="realtime_token"),
    path("heartbeat/",      StreamHeartbeatView.as_view(),      name="stream_heartbeat"),
    path("token/refresh/",  RealtimeTokenRefreshView.as_view(), name="realtime_token_refresh"),
    path("models/",         AvailableModelsView.as_view(),      name="models"),
]