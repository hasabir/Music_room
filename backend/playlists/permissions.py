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

    return False, "Editing is not allowed on this playlist."