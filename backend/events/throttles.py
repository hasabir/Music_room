# events/throttles.py
"""
Per-user rate limits for the actions most likely to be abused:
casting votes, adding songs. These are separate from the auth
throttles (events/throttles.py vs authentication/throttles.py)
so they can be tuned independently.
"""
from rest_framework.throttling import UserRateThrottle


class VoteRateThrottle(UserRateThrottle):
    scope = "vote"


class AddSongRateThrottle(UserRateThrottle):
    scope = "add_song"


class CreateEventRateThrottle(UserRateThrottle):
    scope = "create_event"


class AccessRequestRateThrottle(UserRateThrottle):
    scope = "event_access_request"