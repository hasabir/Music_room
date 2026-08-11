# playlists/services.py
"""
All functions here run inside select_for_update() transactions.

select_for_update() locks the matching rows in the database until the
transaction finishes — so if two requests try to reorder the same
playlist at the exact same moment, the second one simply waits until
the first one's transaction is done, then runs safely on the updated
state. This is what prevents the "competition problematics" (concurrent
edits corrupting the list) that the subject specifically warns about.
"""
from django.db import transaction
from django.db.models import F
from .models import PlaylistSong


def add_song_to_playlist(playlist, song, user):
    """Adds a song to the end of the playlist. Returns the new PlaylistSong."""
    with transaction.atomic():
        current_count = (
            PlaylistSong.objects.select_for_update()
            .filter(playlist=playlist)
            .count()
        )
        return PlaylistSong.objects.create(
            playlist=playlist,
            song=song,
            position=current_count,  # goes to the end
            added_by=user,
        )


def remove_song_from_playlist(playlist, playlist_song_id):
    """
    Removes a song and shifts every song after it back by one position,
    so there are never gaps in the numbering (0, 1, 2, 3...).
    Returns True if something was removed, False if not found.
    """
    with transaction.atomic():
        try:
            target = (
                PlaylistSong.objects.select_for_update()
                .get(id=playlist_song_id, playlist=playlist)
            )
        except PlaylistSong.DoesNotExist:
            return False

        removed_position = target.position
        target.delete()

        # Shift everything after the removed song back by one, closing the gap
        (
            PlaylistSong.objects.select_for_update()
            .filter(playlist=playlist, position__gt=removed_position)
            .update(position=F("position") - 1)
        )
        return True


def move_song(playlist, playlist_song_id, new_position):
    """
    Moves a song to a new position, shifting everything in between
    to make room. Returns the updated PlaylistSong, or None if not found.
    """
    with transaction.atomic():
        try:
            target = (
                PlaylistSong.objects.select_for_update()
                .get(id=playlist_song_id, playlist=playlist)
            )
        except PlaylistSong.DoesNotExist:
            return None

        old_position = target.position
        max_position = (
            PlaylistSong.objects.select_for_update()
            .filter(playlist=playlist)
            .count() - 1
        )
        new_position = max(0, min(new_position, max_position))  # clamp to valid range

        if new_position == old_position:
            return target  # nothing to do

        if new_position > old_position:
            # Moving DOWN the list: shift everything in (old, new] up by one
            (
                PlaylistSong.objects.select_for_update()
                .filter(playlist=playlist, position__gt=old_position, position__lte=new_position)
                .update(position=F("position") - 1)
            )
        else:
            # Moving UP the list: shift everything in [new, old) down by one
            (
                PlaylistSong.objects.select_for_update()
                .filter(playlist=playlist, position__gte=new_position, position__lt=old_position)
                .update(position=F("position") + 1)
            )

        target.position = new_position
        target.save(update_fields=["position"])
        return target