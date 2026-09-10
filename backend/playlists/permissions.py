# playlists/permissions.py
"""
Plain-function permission checks for playlists, mirroring events/permissions.py.
"""


def can_user_see_playlist(user, playlist):
    """
    Public -> anyone can view.
    Private -> only the owner or an invited collaborator.
    """
    if playlist.visibility == "public":
        return True

    if playlist.owner_id == user.id:
        return True

    return playlist.collaborators.filter(collaborator=user).exists()


def can_user_edit_playlist(user, playlist):
    """
    Must be able to see the playlist first.
    Then: everyone (with access) can edit, OR only invited collaborators + owner.
    Returns (allowed: bool, reason: str).
    """
    if not can_user_see_playlist(user, playlist):
        return False, "You do not have access to this playlist."

    if playlist.owner_id == user.id:
        return True, ""

    if playlist.edit_permission == "everyone":
        return True, ""

    if playlist.edit_permission == "invited_only":
        if playlist.collaborators.filter(collaborator=user).exists():
            return True, ""
        return False, "Only invited collaborators can edit this playlist."

    if playlist.edit_permission == "owner_only":
        return False, "Only the owner can edit this playlist."

    return False, "Editing is not allowed on this playlist."


def _collaborator_for(user, playlist):
    return playlist.collaborators.filter(collaborator=user).first()


# Bonus: Free vs. Premium subscription (see docs/SUBSCRIPTION_BONUS.md).
# Editing ANY playlist — public or private — requires Premium, regardless
# of the playlist's own edit_permission — even "everyone can edit" is
# overridden, and there is deliberately no owner exemption. Originally
# scoped to public playlists only; broadened to also cover private ones
# (still no owner exemption) once it was confirmed that editing a private
# playlist should require *both* access (owner/invite/edit_permission)
# and Premium, not access alone.
_PREMIUM_REQUIRED_REASON = (
    "Editing a playlist requires Premium — upgrade your account to add, "
    "reorder, or remove songs."
)
_PREMIUM_REQUIRED_CODE = "playlist_edit_requires_premium"


def can_user_add_songs(user, playlist):
    if not can_user_see_playlist(user, playlist):
        return False, "You do not have access to this playlist.", ""
    if not user.is_premium:
        return False, _PREMIUM_REQUIRED_REASON, _PREMIUM_REQUIRED_CODE
    if playlist.owner_id == user.id or playlist.edit_permission == "everyone":
        return True, "", ""
    collaborator = _collaborator_for(user, playlist)
    if collaborator and collaborator.can_add_songs:
        return True, "", ""
    return False, "The playlist owner has not allowed you to add songs.", ""


def can_user_reorder_songs(user, playlist):
    if not can_user_see_playlist(user, playlist):
        return False, "You do not have access to this playlist.", ""
    if not user.is_premium:
        return False, _PREMIUM_REQUIRED_REASON, _PREMIUM_REQUIRED_CODE
    if playlist.owner_id == user.id or playlist.edit_permission == "everyone":
        return True, "", ""
    collaborator = _collaborator_for(user, playlist)
    if collaborator and collaborator.can_reorder_songs:
        return True, "", ""
    return False, "The playlist owner has not allowed you to reorder songs.", ""


def can_user_manage_collaborators(user, playlist):
    if playlist.owner_id == user.id:
        return True
    collaborator = _collaborator_for(user, playlist)
    return bool(collaborator and collaborator.can_manage_collaborators)
