# events/serializers.py
from django.utils import timezone
from rest_framework import serializers
from profiles.serializers import _actor_display_name
from .models import Event, EventGuest, EventMembership, Song, EventSong, Vote, EventAccessRequest


class EventSerializer(serializers.ModelSerializer):
    host = serializers.StringRelatedField(read_only=True)
    song_count = serializers.ReadOnlyField()
    voting_is_open = serializers.ReadOnlyField()
    current_song = serializers.SerializerMethodField()
    current_position_seconds = serializers.SerializerMethodField()
    is_member = serializers.SerializerMethodField()

    class Meta:
        model = Event
        fields = [
            "id", "host", "title", "description", "cover_preset", "visibility", "status", "vote_permission",
            "time_restriction_enabled", "voting_opens_at", "voting_closes_at",
            "location_restriction_enabled",
            "venue_center_latitude", "venue_center_longitude", "allowed_distance_meters",
            "song_count", "voting_is_open", "is_member",
            "current_song", "current_position_seconds",
            "created_at", "updated_at",
        ]
        read_only_fields = [
            "id", "host", "song_count", "voting_is_open", "is_member",
            "current_song", "current_position_seconds",
            "created_at", "updated_at",
        ]

    def get_is_member(self, obj):
        """Whether the signed-in user has self-joined this event via
        `POST .../join/` (an `EventMembership` row) — distinct from being
        the host or an invited guest. Lets the client tell a public event
        it's already joined apart from one it hasn't discovered yet."""
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return False
        return obj.members.filter(member=request.user).exists()

    def get_current_song(self, obj):
        if obj.current_song_id is None:
            return None
        return EventSongSerializer(obj.current_song, context=self.context).data

    def get_current_position_seconds(self, obj):
        """
        Elapsed playback position, derived fresh from the persisted start
        timestamp rather than stored — see `Event.current_song_started_at`.
        Clamped to the song's playable length when that's known.
        """
        if obj.current_song_id is None or obj.current_song_started_at is None:
            return None
        elapsed = (timezone.now() - obj.current_song_started_at).total_seconds()
        duration = obj.current_song.song.effective_duration_seconds
        if duration is not None:
            elapsed = min(elapsed, duration)
        return max(elapsed, 0)

    def _current(self, attrs, field):
        """Incoming value for `field` if present in this request, else the
        existing instance's current value (or None on create) — so a
        partial PATCH that doesn't touch a restriction's fields is
        validated against what's already saved, not treated as missing."""
        return attrs.get(field, getattr(self.instance, field, None))

    def validate(self, attrs):
        # Two independent restrictions, each with its own required-fields
        # group — replaces the old single `location_time_restricted`
        # combined check. Each is validated (and reported) on its own, so
        # enabling only one never mentions the other's fields.
        if self._current(attrs, "time_restriction_enabled"):
            required_fields = ["voting_opens_at", "voting_closes_at"]
            missing = [f for f in required_fields if self._current(attrs, f) is None]
            if missing:
                raise serializers.ValidationError({
                    "detail": f"These fields are required when time_restriction_enabled "
                              f"is true: {', '.join(missing)}"
                })

        if self._current(attrs, "location_restriction_enabled"):
            required_fields = [
                "venue_center_latitude", "venue_center_longitude", "allowed_distance_meters",
            ]
            missing = [f for f in required_fields if self._current(attrs, f) is None]
            if missing:
                raise serializers.ValidationError({
                    "detail": f"These fields are required when location_restriction_enabled "
                              f"is true: {', '.join(missing)}"
                })

        return attrs


class EventGuestSerializer(serializers.ModelSerializer):
    guest_email = serializers.EmailField(source="guest.email", read_only=True)
    guest_username = serializers.CharField(source="guest.username", read_only=True)
    guest_display_name = serializers.SerializerMethodField()

    class Meta:
        model = EventGuest
        fields = [
            "id", "event", "guest", "guest_email", "guest_username", "guest_display_name",
            "rsvp_status", "invited_at",
        ]
        read_only_fields = [
            "id", "invited_at", "guest_email", "guest_username", "guest_display_name", "rsvp_status",
        ]

    def get_guest_display_name(self, obj):
        return _actor_display_name(obj.guest)


class SongSerializer(serializers.ModelSerializer):
    class Meta:
        model = Song
        fields = [
            "id", "external_id", "title", "artist", "duration_seconds",
            "album_art_url", "preview_url", "playback_type",
        ]
        read_only_fields = ["id"]


class AddSongToQueueSerializer(serializers.Serializer):
    """Used for POSTing a new song into an event's queue (creates Song + EventSong together)."""
    title = serializers.CharField(max_length=200)
    artist = serializers.CharField(max_length=200)
    duration_seconds = serializers.IntegerField(required=False, allow_null=True)
    external_id = serializers.CharField(max_length=100, required=False, allow_blank=True)
    album_art_url = serializers.URLField(max_length=500, required=False, allow_blank=True)
    preview_url = serializers.URLField(max_length=500, required=False, allow_blank=True)
    playback_type = serializers.ChoiceField(
        choices=Song.PLAYBACK_TYPE_CHOICES, required=False, default="preview",
    )


class EventSongSerializer(serializers.ModelSerializer):
    song = SongSerializer(read_only=True)
    added_by_email = serializers.EmailField(source="added_by.email", read_only=True)
    vote_count = serializers.ReadOnlyField()
    has_voted = serializers.SerializerMethodField()

    class Meta:
        model = EventSong
        fields = [
            "id", "event", "song", "added_by_email", "status",
            "vote_count", "has_voted", "added_at",
        ]
        read_only_fields = fields

    def get_has_voted(self, obj):
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return False
        return obj.votes.filter(voter=request.user).exists()

class InviteGuestSerializer(serializers.Serializer):
    """Used for POSTing a new guest invitation."""
    user_id = serializers.IntegerField()


class EventMembershipSerializer(serializers.ModelSerializer):
    member_email = serializers.EmailField(source="member.email", read_only=True)
    member_username = serializers.CharField(source="member.username", read_only=True)
    member_display_name = serializers.SerializerMethodField()

    class Meta:
        model = EventMembership
        fields = [
            "id", "event", "member", "member_email", "member_username", "member_display_name", "joined_at",
        ]
        read_only_fields = fields

    def get_member_display_name(self, obj):
        return _actor_display_name(obj.member)


class EventAccessRequestSerializer(serializers.ModelSerializer):
    requester_email = serializers.EmailField(source="requester.email", read_only=True)

    class Meta:
        model = EventAccessRequest
        fields = ["id", "event", "requester", "requester_email", "status", "requested_at", "decided_at"]
        read_only_fields = fields


class DecideAccessRequestSerializer(serializers.Serializer):
    """Used for POSTing a host's decision on an access request."""
    approve = serializers.BooleanField()
