# playlists/services.py
"""Playlist edits lock the parent row before reading or changing song order.

All edits to one playlist serialize; different playlists can edit independently.
The parent exists even when there are no songs, unlike a child-row lock.
"""
from django.db import transaction
from django.db.models import F
from .models import Playlist, PlaylistSong


class DuplicatePlaylistSong(ValueError):
    pass


def add_song_to_playlist(playlist, song, user):
    """Adds a song to the end of the playlist. Returns the new PlaylistSong."""
    with transaction.atomic():
        # Serialize all edits, including additions to an empty playlist.
        Playlist.objects.select_for_update().get(pk=playlist.pk)
        if PlaylistSong.objects.filter(playlist=playlist, song=song).exists():
            raise DuplicatePlaylistSong("This song is already in the playlist.")
        current_count = (
            PlaylistSong.objects
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
        # Serialize all edits, including additions to an empty playlist.
        Playlist.objects.select_for_update().get(pk=playlist.pk)
        try:
            target = (
                PlaylistSong.objects
                .get(id=playlist_song_id, playlist=playlist)
            )
        except PlaylistSong.DoesNotExist:
            return False

        removed_position = target.position
        target.delete()

        # Shift everything after the removed song back by one, closing the gap
        (
            PlaylistSong.objects
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
        # Serialize all edits, including additions to an empty playlist.
        Playlist.objects.select_for_update().get(pk=playlist.pk)
        try:
            target = (
                PlaylistSong.objects
                .get(id=playlist_song_id, playlist=playlist)
            )
        except PlaylistSong.DoesNotExist:
            return None

        old_position = target.position
        max_position = (
            PlaylistSong.objects
            .filter(playlist=playlist)
            .count() - 1
        )
        new_position = max(0, min(new_position, max_position))  # clamp to valid range

        if new_position == old_position:
            return target  # nothing to do

        if new_position > old_position:
            # Moving DOWN the list: shift everything in (old, new] up by one
            (
                PlaylistSong.objects
                .filter(playlist=playlist, position__gt=old_position, position__lte=new_position)
                .update(position=F("position") - 1)
            )
        else:
            # Moving UP the list: shift everything in [new, old) down by one
            (
                PlaylistSong.objects
                .filter(playlist=playlist, position__gte=new_position, position__lt=old_position)
                .update(position=F("position") + 1)
            )

        target.position = new_position
        target.save(update_fields=["position"])
        return target