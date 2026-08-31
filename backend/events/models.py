# events/models.py
from datetime import timedelta

from django.db import models
from django.conf import settings
from django.utils import timezone


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

    # The event's authoritative "on air" state. Persisted (not recomputed
    # per-request from scratch) so a position can be derived from
    # `current_song_started_at` — see `sync_current_song`. `SET_NULL` (not
    # CASCADE) because losing this pointer should never take the event down
    # with it; `sync_current_song` just re-picks a leader on the next call.
    current_song = models.ForeignKey(
        "EventSong", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
        help_text="The queue entry currently 'on air', authoritative on "
                   "the backend regardless of who's connected. Set only "
                   "by `sync_current_song`.",
    )
    current_song_started_at = models.DateTimeField(
        null=True, blank=True,
        help_text="When `current_song` started playing from position 0. "
                   "Playback position is always derived as "
                   "now() - this timestamp, never stored directly.",
    )

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

    def _highest_voted_unplayed(self):
        """The best not-yet-played candidate to be current, ties broken by
        queue order (i.e. whichever was added first)."""
        unplayed = list(self.queue.exclude(status="played"))
        if not unplayed:
            return None
        return sorted(unplayed, key=lambda es: es.vote_count, reverse=True)[0]

    def sync_current_song(self):
        """
        The single place that decides what's authoritatively "on air" and
        advances it as far as real time allows — even if nobody has had
        this event open since it started. Call before reading queue/
        playback state, and after any queue-affecting mutation (vote,
        retract, add song).

        There's no background worker in this project, so forward progress
        isn't ticked on a timer — it's caught up lazily, right here, on
        whatever request happens to ask: if `current_song`'s playable
        duration has already fully elapsed by wall-clock time, it's
        retired and the next leader picked, repeating (in case many
        songs' worth of time passed while no one was watching) until a
        song is genuinely still mid-playback or the queue runs dry.

        A song already playing is never interrupted by a vote, no matter
        how many votes a different song picks up while it plays — voting
        only ever reorders the queue (who leads once the current song's
        time is up), it never cuts off what's already on air. That's what
        lets everyone keep voting freely without worrying a vote will
        yank the track out from under the room mid-play.
        """
        now = timezone.now()
        changed = False
        # When a song's time has genuinely run out, the *next* song is
        # treated as having started right when that window ran out — not
        # "now" — so a long-unwatched gap correctly keeps advancing
        # through however many songs' worth of time actually passed,
        # rather than only ever hopping one song per call.
        next_start = now

        while True:
            if self.current_song is None:
                leader = self._highest_voted_unplayed()
                if leader is None:
                    break
                leader.status = "playing"
                leader.save(update_fields=["status"])
                self.current_song = leader
                self.current_song_started_at = next_start
                next_start = now
                changed = True
                continue

            duration = self.current_song.song.effective_duration_seconds
            if duration is None:
                break  # unknown length — can't tell it's over, leave it playing

            elapsed = (now - self.current_song_started_at).total_seconds()
            if elapsed < duration:
                break  # still mid-playback — never interrupted by votes

            # Time's up — retire it and loop again to pick whoever leads next.
            next_start = self.current_song_started_at + timedelta(seconds=duration)
            self.current_song.status = "played"
            self.current_song.save(update_fields=["status"])
            self.current_song = None
            self.current_song_started_at = None
            changed = True

        if changed:
            self.save(update_fields=["current_song", "current_song_started_at"])
        return self.current_song


class EventGuest(models.Model):
    """
    A "collaborator": one person the host has invited, granting both
    private-event visibility and invited_only voting rights. Not limited to
    private events — a public event can also invite guests specifically to
    hand out invited_only voting rights (public visibility + invite-gated
    voting), which is exactly what an EventGuest row on a public event
    represents.
    """

    RSVP_PENDING = "pending"
    RSVP_ACCEPTED = "accepted"
    RSVP_DECLINED = "declined"
    RSVP_STATUS_CHOICES = [
        (RSVP_PENDING, "Pending"),
        (RSVP_ACCEPTED, "Accepted"),
        (RSVP_DECLINED, "Declined"),
    ]

    event = models.ForeignKey(Event, on_delete=models.CASCADE, related_name="guests")
    guest = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="event_invitations")
    rsvp_status = models.CharField(max_length=10, choices=RSVP_STATUS_CHOICES, default=RSVP_PENDING)
    invited_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("event", "guest")  # can't invite the same person twice
        ordering = ["-invited_at"]

    def __str__(self):
        return f"{self.guest.email} invited to {self.event.title} ({self.rsvp_status})"


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


class EventAccessRequest(models.Model):
    """
    A request from a non-guest to gain access to a private event — mirrors
    `playlists.PlaylistAccessRequest`. Approving a request simply creates
    an `EventGuest`, which already grants both private-event visibility
    and invited_only voting rights.
    """

    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_DENIED = "denied"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending"),
        (STATUS_APPROVED, "Approved"),
        (STATUS_DENIED, "Denied"),
    ]

    event = models.ForeignKey(Event, on_delete=models.CASCADE, related_name="access_requests")
    requester = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="event_access_requests"
    )
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default=STATUS_PENDING)
    requested_at = models.DateTimeField(auto_now_add=True)
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-requested_at"]

    def __str__(self):
        return f"{self.requester.email} -> {self.event.title} ({self.status})"


class Song(models.Model):
    """A song known to the system (general catalog, not tied to any one event)."""

    # How long the Deezer preview clip actually plays for, regardless of
    # the source track's real length — see `effective_duration_seconds`.
    PREVIEW_CLIP_SECONDS = 30

    PLAYBACK_TYPE_CHOICES = [
        ("preview", "~30-second preview clip (Deezer)"),
        ("full", "Full-length stream (Audius)"),
    ]

    external_id = models.CharField(
        max_length=100, blank=True,
        help_text="ID from the music SDK/API, once integrated. Optional for now."
    )
    title = models.CharField(max_length=200)
    artist = models.CharField(max_length=200)
    duration_seconds = models.PositiveIntegerField(null=True, blank=True)
    album_art_url = models.URLField(max_length=500, blank=True, default="")
    preview_url = models.URLField(max_length=500, blank=True, default="")
    playback_type = models.CharField(
        max_length=10, choices=PLAYBACK_TYPE_CHOICES, default="preview",
        help_text="Whether `preview_url` plays a short clip or the full "
                   "track — see `effective_duration_seconds`.",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["title"]

    def __str__(self):
        return f"{self.title} — {self.artist}"

    @property
    def effective_duration_seconds(self):
        """
        How long this song is treated as "current" for by backend playback
        timing (`Event.sync_current_song`). A `preview` is always exactly
        `PREVIEW_CLIP_SECONDS`, regardless of what `duration_seconds` says
        the real commercial track's length is — that metadata describes
        the *song*, not the clip actually sitting at `preview_url`, which
        never plays for longer than this no matter what. Treating a
        `preview` as current for any longer than that would leave every
        listener's local player sitting on a naturally-finished (silent or
        looping) clip while the backend kept the room waiting on a
        duration nothing can actually play. A `full` (Audius) stream has
        no such gap, so its real metadata duration is used as-is (`None`
        if unknown, meaning it plays indefinitely).
        """
        if self.playback_type == "preview":
            return self.PREVIEW_CLIP_SECONDS
        return self.duration_seconds


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
