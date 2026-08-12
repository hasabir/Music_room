# events/serializers.py
from rest_framework import serializers
from .models import Event, EventGuest, Song, EventSong, Vote


class EventSerializer(serializers.ModelSerializer):
    host = serializers.StringRelatedField(read_only=True)
    song_count = serializers.ReadOnlyField()
    voting_is_open = serializers.ReadOnlyField()

    class Meta:
        model = Event
        fields = [
            "id", "host", "title", "visibility", "vote_permission",
            "venue_center_latitude", "venue_center_longitude", "allowed_distance_meters",
            "voting_opens_at", "voting_closes_at",
            "song_count", "voting_is_open",
            "created_at", "updated_at",
        ]
        read_only_fields = ["id", "host", "song_count", "voting_is_open", "created_at", "updated_at"]

    def validate(self, attrs):
        vote_permission = attrs.get("vote_permission", getattr(self.instance, "vote_permission", None))

        if vote_permission == "location_time_restricted":
            required_fields = [
                "venue_center_latitude", "venue_center_longitude",
                "allowed_distance_meters", "voting_opens_at", "voting_closes_at",
            ]
            missing = [
                f for f in required_fields
                if attrs.get(f, getattr(self.instance, f, None)) is None
            ]
            if missing:
                raise serializers.ValidationError({
                    "detail": f"These fields are required when vote_permission is "
                              f"'location_time_restricted': {', '.join(missing)}"
                })

        return attrs


class EventGuestSerializer(serializers.ModelSerializer):
    guest_email = serializers.EmailField(source="guest.email", read_only=True)

    class Meta:
        model = EventGuest
        fields = ["id", "event", "guest", "guest_email", "invited_at"]
        read_only_fields = ["id", "invited_at", "guest_email"]


class SongSerializer(serializers.ModelSerializer):
    class Meta:
        model = Song
        fields = ["id", "external_id", "title", "artist", "duration_seconds"]
        read_only_fields = ["id"]


class AddSongToQueueSerializer(serializers.Serializer):
    """Used for POSTing a new song into an event's queue (creates Song + EventSong together)."""
    title = serializers.CharField(max_length=200)
    artist = serializers.CharField(max_length=200)
    duration_seconds = serializers.IntegerField(required=False, allow_null=True)
    external_id = serializers.CharField(max_length=100, required=False, allow_blank=True)


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
 