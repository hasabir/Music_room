# events/models.py
from django.db import models
from django.conf import settings


class Event(models.Model):
    """A party/gathering where people add songs to a shared queue and vote on them."""

    VISIBILITY_CHOICES = [
        ("public", "Public — anyone can find and join"),
        ("private", "Private — invite only"),
    ]
    VOTE_PERMISSION_CHOICES = [
        ("everyone", "Everyone can vote"),
        ("invited_only", "Only invited guests can vote"),
        ("location_time_restricted", "Only people at the venue, during the time window, can vote"),
    ]
    COVER_PRESET_CHOICES = [
        ("party", "Party"),
        ("night_vibe", "Night vibe"),
        ("dj", "DJ"),
        ("summer_vibe", "Summer vibe"),
        ("rain", "Rain"),
        ("coding_vibe", "Coding vibe"),
        ("after_dark", "After dark"),
        ("vibes", "Vibes"),
    ]

    host = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="hosted_events",
        help_text="The user who created this event."
    )
    title = models.CharField(max_length=100)
    description = models.TextField(max_length=500, blank=True, default="")
    cover_preset = models.CharField(max_length=20, choices=COVER_PRESET_CHOICES, default="party")

    visibility = models.CharField(max_length=10, choices=VISIBILITY_CHOICES, default="public")
    vote_permission = models.CharField(max_length=30, choices=VOTE_PERMISSION_CHOICES, default="everyone")

    # Only filled in when vote_permission == "location_time_restricted"
    venue_center_latitude = models.FloatField(null=True, blank=True)
    venue_center_longitude = models.FloatField(null=True, blank=True)
    allowed_distance_meters = models.PositiveIntegerField(null=True, blank=True)
    voting_opens_at = models.DateTimeField(null=True, blank=True)
    voting_closes_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.title

    @property
    def song_count(self):
        """How many songs are currently in this event's queue."""
        return self.queue.count()

    @property
    def voting_is_open(self):
        """
        Whether voting can happen right now, based purely on the
        'at least 2 songs' rule. Permission checks (who is allowed
        to vote) are handled separately in the view/permission layer.
        """
        return self.song_count >= 2


class EventGuest(models.Model):
    """One person on the guest list of a private event."""

    event = models.ForeignKey(Event, on_delete=models.CASCADE, related_name="guests")
    guest = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="event_invitations")
    invited_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("event", "guest")  # can't invite the same person twice
        ordering = ["-invited_at"]

    def __str__(self):
        return f"{self.guest.email} invited to {self.event.title}"


class EventMembership(models.Model):
    """
    Tracks that a user has explicitly joined a public event/room.

    Deliberately separate from `EventGuest`: `EventGuest` is host-granted
    and also drives `invited_only` voting rights (see
    `permissions.can_user_vote`), so self-joining a public event must
    never create an `EventGuest` row — that would silently grant
    invited-only voting permission on top of just "joining".
    """

    event = models.ForeignKey(Event, on_delete=models.CASCADE, related_name="members")
    member = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="joined_events")
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("event", "member")
        ordering = ["-joined_at"]

    def __str__(self):
        return f"{self.member.email} joined {self.event.title}"


class Song(models.Model):
    """A song known to the system (general catalog, not tied to any one event)."""

    external_id = models.CharField(
        max_length=100, blank=True,
        help_text="ID from the music SDK/API, once integrated. Optional for now."
    )
    title = models.CharField(max_length=200)
    artist = models.CharField(max_length=200)
    duration_seconds = models.PositiveIntegerField(null=True, blank=True)
    album_art_url = models.URLField(max_length=500, blank=True, default="")
    preview_url = models.URLField(max_length=500, blank=True, default="")

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["title"]

    def __str__(self):
        return f"{self.title} — {self.artist}"


class EventSong(models.Model):
    """A song that has been added to one specific event's queue."""

    STATUS_CHOICES = [
        ("queued", "Waiting in the queue"),
        ("playing", "Currently playing"),
        ("played", "Already played"),
    ]

    event = models.ForeignKey(Event, on_delete=models.CASCADE, related_name="queue")
    song = models.ForeignKey(Song, on_delete=models.CASCADE, related_name="added_to_events")
    added_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="songs_added"
    )
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default="queued")
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("event", "song")  # same song can't appear twice in one event's queue
        ordering = ["added_at"]

    def __str__(self):
        return f"{self.song} in {self.event}"

    @property
    def vote_count(self):
        return self.votes.count()


class Vote(models.Model):
    """One person's vote for one song, in one event."""

    event_song = models.ForeignKey(EventSong, on_delete=models.CASCADE, related_name="votes")
    voter = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="votes_cast")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        # THE key rule: one vote per person per song — enforced by the database itself,
        # even if many requests arrive at the exact same time (handles the
        # "competition problematics" the subject warns about).
        unique_together = ("event_song", "voter")
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.voter.email} voted for {self.event_song.song}"
