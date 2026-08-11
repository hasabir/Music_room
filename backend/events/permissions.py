# events/permissions.py
import math
from django.utils import timezone


def can_user_see_event(user, event):
    """
    Can this user even find/view this event?
    Public -> yes for everyone.
    Private -> only the host or an invited guest.
    """
    if event.visibility == "public":
        return True

    if event.host_id == user.id:
        return True

    return event.guests.filter(guest=user).exists()


def can_user_vote(user, event, user_latitude=None, user_longitude=None):
    """
    Can this user cast a vote on this event right now?
    Returns (allowed: bool, reason: str) so the view can return a clear error message.
    """
    # Must be able to see the event at all first
    if not can_user_see_event(user, event):
        return False, "You do not have access to this event."

    # Must have at least 2 songs in the queue before any voting can happen
    if not event.voting_is_open:
        return False, "At least 2 songs must be in the queue before voting can start."

    if event.vote_permission == "everyone":
        return True, ""

    if event.vote_permission == "invited_only":
        if event.host_id == user.id:
            return True, ""
        if event.guests.filter(guest=user).exists():
            return True, ""
        return False, "Only invited guests can vote on this event."

    if event.vote_permission == "location_time_restricted":
        now = timezone.now()

        if event.voting_opens_at and now < event.voting_opens_at:
            return False, "Voting has not opened yet for this event."
        if event.voting_closes_at and now > event.voting_closes_at:
            return False, "Voting has closed for this event."

        if user_latitude is None or user_longitude is None:
            return False, "Your location is required to vote on this event."

        distance = _distance_in_meters(
            event.venue_center_latitude, event.venue_center_longitude,
            user_latitude, user_longitude
        )
        if distance > event.allowed_distance_meters:
            return False, "You must be near the event venue to vote."

        return True, ""

    return False, "Voting is not allowed on this event."


def _distance_in_meters(lat1, lon1, lat2, lon2):
    """Haversine formula — straight-line distance between two GPS points, in meters."""
    R = 6371000  # Earth's radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)

    a = (math.sin(d_phi / 2) ** 2
         + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c