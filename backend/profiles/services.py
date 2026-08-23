# profiles/services.py
from .models import Profile


def create_profile_for_user(user):
    """
    Ensures a `Profile` row exists for `user`, creating an empty one if
    needed. Called right when a user becomes verified (email verification,
    or Google sign-in — which is auto-verified), so the profile exists
    eagerly instead of only being lazily created on the first
    `GET /profile/me/` (see `MyProfileView.get_object`, which still does
    the same `get_or_create` as a safety net for accounts that predate
    this hook).
    """
    profile, _ = Profile.objects.get_or_create(user=user)
    return profile
