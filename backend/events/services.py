# events/services.py
"""
FREE-tier suggestion/vote limits, and the locking helper both share —
see docs/SUBSCRIPTION_BONUS.md for the full design writeup. Mirrors
playlists/services.py's "runs inside select_for_update() transactions"
convention: same pattern (SELECT ... FOR UPDATE inside
transaction.atomic()), applied at a new per-(event, user) anchor point,
not a second/inconsistent locking strategy.
"""
from .models import EventParticipation

FREE_SUGGESTION_LIMIT = 10
FREE_VOTE_LIMIT = 20


def lock_participation(event, user):
    """
    Returns this (event, user)'s EventParticipation row, locked with
    SELECT ... FOR UPDATE for the rest of the caller's enclosing
    transaction.atomic() block. Call this as the first statement inside
    one, before checking/incrementing any limit.

    get_or_create() can't itself take select_for_update(), so creation
    is a separate step first — but it needs no transaction of its own:
    get_or_create() already wraps its create() in a transaction.atomic(),
    which nests as a savepoint inside the caller's already-open one, and
    its built-in IntegrityError-catch-and-reget (backed by this model's
    unique_together=("event", "user")) is what makes the very first
    request from a given user for a given event safe even if it
    somehow raced itself.

    Locking a per-(event, user) row — rather than the whole Event row —
    means only this one user's own concurrent suggest/vote attempts
    serialize against each other; other users acting on the same event
    at the same time are never blocked by this.
    """
    EventParticipation.objects.get_or_create(event=event, user=user)
    return EventParticipation.objects.select_for_update().get(event=event, user=user)
