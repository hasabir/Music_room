# events/services.py
"""
FREE-tier suggestion/vote limits, and the locking helper both share —
see docs/SUBSCRIPTION_BONUS.md for the full design writeup. The cap is
per calendar day, across every event a user takes part in — not per
event — so the lock anchor is a (user, date) row, not a (event, user)
one. Mirrors playlists/services.py's "runs inside select_for_update()
transactions" convention: same pattern (SELECT ... FOR UPDATE inside
transaction.atomic()), applied at this per-(user, date) anchor point,
not a second/inconsistent locking strategy.
"""
from django.utils import timezone

from .models import DailyParticipation

FREE_SUGGESTION_LIMIT = 10
FREE_VOTE_LIMIT = 20


def lock_participation(user):
    """
    Returns this user's DailyParticipation row for today (the server's
    local date — see `timezone.localdate()`), locked with
    SELECT ... FOR UPDATE for the rest of the caller's enclosing
    transaction.atomic() block. Call this as the first statement inside
    one, before checking/incrementing either limit.

    get_or_create() can't itself take select_for_update(), so creation
    is a separate step first — but it needs no transaction of its own:
    get_or_create() already wraps its create() in a transaction.atomic(),
    which nests as a savepoint inside the caller's already-open one, and
    its built-in IntegrityError-catch-and-reget (backed by this model's
    unique_together=("user", "date")) is what makes the very first
    request from a given user on a given day safe even if it somehow
    raced itself.

    Locking a per-(user, date) row — rather than any per-event row —
    means only this one user's own concurrent suggest/vote attempts
    serialize against each other, across every event they touch today;
    other users acting at the same time are never blocked by this.
    """
    today = timezone.localdate()
    DailyParticipation.objects.get_or_create(user=user, date=today)
    return DailyParticipation.objects.select_for_update().get(user=user, date=today)
