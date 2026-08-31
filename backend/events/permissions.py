# events/permissions.py
import math
from django.utils import timezone


def can_user_see_event(user, event):
    """
    Can this user even find/view this event?
    Host -> always yes, regardless of status — the host retains full
    access to manage/inspect an event no matter its lifecycle state.
    Canceled -> nobody else at all, regardless of visibility or prior
    EventGuest/EventMembership status — cancelling locks everyone else
    out, even someone who had already joined before the cancellation.
    Deleted -> the opposite of canceled: only a *past* guest or member
    can still fetch it (so the client can show "this event has been
    deleted"), a stranger who never had access gets nothing new — it's
    already excluded from every listing regardless (see
    EventListCreateView.get_queryset).
    Otherwise (live or closed): public -> yes for everyone; private ->
    only an invited guest. (Closed events stay just as visible/enterable
    as live ones — see can_user_vote and EventQueueView for the one
    thing closed actually blocks: suggesting new tracks.)
    """
    if event.host_id == user.id:
        return True

    if event.status == "canceled":
        return False

    if event.status == "deleted":
        return event.guests.filter(guest=user).exists() or event.members.filter(member=user).exists()

    if event.visibility == "public":
        return True

    return event.guests.filter(guest=user).exists()


def can_user_vote(user, event, user_latitude=None, user_longitude=None):
    """
    Can this user cast a vote on this event right now?
    Returns (allowed: bool, reason: str) so the view can return a clear error message.

    vote_permission (who's allowed at all) and the two restriction toggles
    (when/where they're allowed) are independent and composable — an
    `everyone` event can still have a time and/or location restriction
    layered on top, same as an `invited_only` one. Checked in order: see
    event -> enough songs -> invited-only gate -> time restriction (if
    enabled) -> location restriction (if enabled). Both restrictions must
    pass if both are enabled; time is checked first, so a vote attempt
    failing both surfaces the time message.
    """
    # Must be able to see the event at all first
    if not can_user_see_event(user, event):
        return False, "You do not have access to this event."

    # A past participant can still *see* a deleted event (so the client
    # can show the "deleted" message) but can't act on it anymore —
    # unlike canceled, which already blocks seeing it for everyone but
    # the host, so no separate check is needed there.
    if event.status == "deleted":
        return False, "This event has been deleted."

    # Must have at least 2 songs in the queue before any voting can happen
    if not event.voting_is_open:
        return False, "At least 2 songs must be in the queue before voting can start."

    if event.vote_permission == "invited_only":
        is_host = event.host_id == user.id
        is_guest = event.guests.filter(guest=user).exists()
        if not (is_host or is_guest):
            return False, "Only invited guests can vote on this event."

    if event.time_restriction_enabled:
        now = timezone.now()
        if event.voting_opens_at and now < event.voting_opens_at:
            return False, "Voting has not opened yet for this event."
        if event.voting_closes_at and now > event.voting_closes_at:
            return False, "Voting has closed for this event."

    if event.location_restriction_enabled:
        if user_latitude is None or user_longitude is None:
            return False, "Your location is required to vote on this event."

        distance = _distance_in_meters(
            event.venue_center_latitude, event.venue_center_longitude,
            user_latitude, user_longitude
        )
        if distance > event.allowed_distance_meters:
            return False, "You must be near the event venue to vote."

    return True, ""


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