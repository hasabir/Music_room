# profiles/services.py
from .models import Friendship, Profile


def resolve_avatar(profile):
    """
    The one value to render regardless of source — a preset id when
    `profile.avatar_type` is `"preset"` (the client resolves that against
    its own bundled asset grid), otherwise a plain image URL. Shared by
    `ProfileSerializer.get_avatar` and anywhere else that needs to show a
    user's avatar without duplicating this three-way branch (e.g. event
    participant lists — see `events.serializers.EventGuestSerializer`).
    """
    if profile.avatar_type == "custom":
        return profile.profile_image.url if profile.profile_image else None
    if profile.avatar_type == "external_url":
        return profile.avatar_external_url or None
    return profile.avatar_preset_id or None


def avatar_for_user(user):
    """
    `(avatar, avatar_type)` for `user` — the `User`-level counterpart to
    `resolve_avatar` (which takes a `Profile`), for the many places that
    only have a `User` on hand (friend lists, search results, event
    participant lists, playlist collaborator lists, ...). Defaults to a
    blank preset if `user` somehow has no `Profile` row yet (shouldn't
    happen for a verified user, but these are all read by list endpoints
    — not worth a 500 over).
    """
    profile = getattr(user, "profile", None)
    if profile is None:
        return None, "preset"
    return resolve_avatar(profile), profile.avatar_type


def relationship_status(viewer, target_user):
    """
    `(status, friendship_id)` describing `viewer`'s relationship with
    `target_user` — `"self"` (friendship_id `None`), `"friends"`,
    `"pending_sent"`, `"pending_received"`, or `"none"`. Shared by
    `UserSearchView` and `UserProfileView` so the two never drift on what
    counts as which state.
    """
    if viewer.id == target_user.id:
        return "self", None

    sent = Friendship.objects.filter(sender=viewer, receiver=target_user).first()
    received = Friendship.objects.filter(sender=target_user, receiver=viewer).first()

    if sent and sent.status == "accepted":
        return "friends", sent.id
    if received and received.status == "accepted":
        return "friends", received.id
    if sent and sent.status == "pending":
        return "pending_sent", sent.id
    if received and received.status == "pending":
        return "pending_received", received.id
    return "none", None


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
