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
        ("owner_only", "Only the owner can edit"),
    ]
    # The 5 built-in cover looks a playlist can use instead of an uploaded
    # image. Purely a style key — rendered client-side, nothing to store
    # server-side beyond the id.
    COVER_PRESET_CHOICES = [
        ("sunset", "Sunset"),
        ("neon", "Neon"),
        ("forest", "Forest"),
        ("ocean", "Ocean"),
        ("midnight", "Midnight"),
    ]

    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="owned_playlists"
    )
    title = models.CharField(max_length=100)
    description = models.TextField(max_length=500, blank=True, default="")

    visibility = models.CharField(max_length=10, choices=VISIBILITY_CHOICES, default="public")
    edit_permission = models.CharField(max_length=20, choices=EDIT_PERMISSION_CHOICES, default="everyone")

    # A playlist shows at most one cover: an uploaded image if present,
    # otherwise the chosen preset, otherwise a generated fallback
    # (client-side). Setting one clears the other — see
    # PlaylistSerializer.validate().
    cover_image = models.ImageField(upload_to="playlists/covers/", null=True, blank=True)
    cover_preset = models.CharField(max_length=20, choices=COVER_PRESET_CHOICES, blank=True, default="")

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
    # The owner can tailor what each invitee may do. Existing collaborators
    # keep their previous edit capability after this migration.
    can_add_songs = models.BooleanField(default=True)
    can_reorder_songs = models.BooleanField(default=True)
    can_manage_collaborators = models.BooleanField(default=False)

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


class PlaylistAccessRequest(models.Model):
    """
    A request from a non-collaborator to gain access to a playlist —
    either to view a private one, or to edit an invited_only one. Approving
    a request simply creates a PlaylistCollaborator, which already grants
    both of those depending on the playlist's settings.
    """

    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_DENIED = "denied"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending"),
        (STATUS_APPROVED, "Approved"),
        (STATUS_DENIED, "Denied"),
    ]

    playlist = models.ForeignKey(Playlist, on_delete=models.CASCADE, related_name="access_requests")
    requester = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="playlist_access_requests"
    )
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default=STATUS_PENDING)
    requested_at = models.DateTimeField(auto_now_add=True)
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-requested_at"]

    def __str__(self):
        return f"{self.requester.email} -> {self.playlist.title} ({self.status})"
