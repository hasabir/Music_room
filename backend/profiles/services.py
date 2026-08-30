# profiles/services.py
from .models import Profile


def create_profile_for_user(user, *, avatar_external_url=None):
    """
    Ensures a `Profile` row exists for `user`, creating an empty one if
    needed. Called right when a user becomes verified (email verification,
    or Google sign-in — which is auto-verified), so the profile exists
    eagerly instead of only being lazily created on the first
    `GET /profile/me/` (see `MyProfileView.get_object`, which still does
    the same `get_or_create` as a safety net for accounts that predate
    this hook).

    A freshly *created* row already gets a random preset avatar for free,
    from `Profile.avatar_preset_id`'s field default — no extra step needed
    here for that case. `avatar_external_url`, when given (a social
    sign-in's profile photo — see `GoogleLoginView`), overrides that
    random default so the account starts with the provider's photo
    instead. Ignored if the profile already existed, so a returning
    user's chosen avatar is never overwritten.
    """
    profile, created = Profile.objects.get_or_create(user=user)
    if created and avatar_external_url:
        profile.avatar_type = "external_url"
        profile.avatar_external_url = avatar_external_url
        profile.save(update_fields=["avatar_type", "avatar_external_url"])
    return profile
