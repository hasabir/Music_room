# playlists/models.py
from django.db import models
from django.db.models import Deferrable
from django.conf import settings


class Playlist(models.Model):
    """A collaborative, ordered list of songs."""

    VISIBILITY_CHOICES = [
        ("public", "Public — anyone can view"),
        ("private", "Private — invite only"),
    ]
    EDIT_PERMISSION_CHOICES = [
        ("everyone", "Everyone (with access) can edit"),
        ("invited_only", "Only invited collaborators can edit"),
    ]

    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="owned_playlists"
    )
    title = models.CharField(max_length=100)

    visibility = models.CharField(max_length=10, choices=VISIBILITY_CHOICES, default="public")
    edit_permission = models.CharField(max_length=20, choices=EDIT_PERMISSION_CHOICES, default="everyone")

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.title

    @property
    def song_count(self):
        return self.songs.count()


class PlaylistCollaborator(models.Model):
    """One person allowed to view/edit a private or invited_only playlist."""

    playlist = models.ForeignKey(Playlist, on_delete=models.CASCADE, related_name="collaborators")
    collaborator = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="playlist_invitations"
    )
    invited_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("playlist", "collaborator")

    def __str__(self):
        return f"{self.collaborator.email} on {self.playlist.title}"


class PlaylistSong(models.Model):
    """One song at one position in one playlist."""

    playlist = models.ForeignKey(Playlist, on_delete=models.CASCADE, related_name="songs")
    song = models.ForeignKey("events.Song", on_delete=models.CASCADE, related_name="in_playlists")
    position = models.PositiveIntegerField()
    added_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="playlist_songs_added"
    )
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            # No two songs can share a slot in the same playlist.
            #
            # DEFERRABLE = Deferrable.DEFERRED: Postgres normally checks a
            # unique constraint immediately after each row is modified. When
            # we shift multiple songs' positions in one UPDATE (reordering),
            # a row can momentarily land on a position another not-yet-updated
            # row still occupies — even though the FINAL result is valid.
            # Making the constraint deferred tells Postgres to only check it
            # once, at the end of the transaction, avoiding false failures
            # during a multi-row shift.
            models.UniqueConstraint(
                fields=["playlist", "position"],
                name="unique_position_per_playlist",
                deferrable=Deferrable.DEFERRED,
            ),
            # The same song can't be added twice to the same playlist
            models.UniqueConstraint(fields=["playlist", "song"], name="unique_song_per_playlist"),
        ]
        ordering = ["position"]

    def __str__(self):
        return f"{self.song} at position {self.position} in {self.playlist}"