# api/throttles.py
from rest_framework.throttling import UserRateThrottle


class TrackSearchRateThrottle(UserRateThrottle):
    scope = "track_search"


class TrackPreviewRateThrottle(UserRateThrottle):
    scope = "track_preview"
