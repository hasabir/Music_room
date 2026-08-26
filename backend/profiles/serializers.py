from django.db.models import Q
from rest_framework import serializers

from user.models import User, ActionLog
from events.models import Vote
from playlists.models import Playlist
from .models import Friendship , Profile


class FriendSerializer(serializers.ModelSerializer):

    class Meta:
        model = User
        fields = [
            "id",
            "first_name",
            "last_name",
        ]


class FriendshipSerializer(serializers.ModelSerializer):

    sender = FriendSerializer(read_only=True)
    receiver = FriendSerializer(read_only=True)

    class Meta:
        model = Friendship
        fields = [
            "id",
            "sender",
            "receiver",
            "status",
            "created_at",
            "updated_at",
        ]
        read_only_fields = fields


class ProfileSerializer(serializers.ModelSerializer):

    favorite_genres = serializers.ListField(
        child=serializers.ChoiceField(
            choices=Profile.MUSIC_GENRE_CHOICES
        ),
        required=False,
        allow_empty=True,
    )

    votes_count = serializers.SerializerMethodField()
    playlists_count = serializers.SerializerMethodField()

    class Meta:
        model = Profile
        fields = [
            "id",
            "display_name",
            "bio",
            "location",
            "favorite_artist",
            "phone_number",
            "birthday",
            "profile_image",
            "favorite_genres",
            "field_visibility",
            "votes_count",
            "playlists_count",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "votes_count",
            "playlists_count",
            "created_at",
            "updated_at",
        ]

    def get_votes_count(self, obj):
        return obj.user.votes_cast.count()

    def get_playlists_count(self, obj):
        return Playlist.objects.filter(
            Q(owner=obj.user) | Q(collaborators__collaborator=obj.user)
        ).distinct().count()

    def validate_field_visibility(self, value):
        if not isinstance(value, dict):
            raise serializers.ValidationError("field_visibility must be an object.")

        allowed_fields = {
            "bio", "location", "favorite_artist", "phone_number", "birthday", "activity",
        }
        allowed_tiers = {tier for tier, _ in Profile.VISIBILITY_CHOICES}

        for field, tier in value.items():
            if field not in allowed_fields:
                raise serializers.ValidationError(f"Unknown field '{field}'.")
            if tier not in allowed_tiers:
                raise serializers.ValidationError(f"Invalid visibility '{tier}' for '{field}'.")

        return value

    def update(self, instance, validated_data):
        incoming_visibility = validated_data.pop("field_visibility", None)
        if incoming_visibility is not None:
            instance.field_visibility = {**instance.field_visibility, **incoming_visibility}
        return super().update(instance, validated_data)


def _actor_display_name(user):
    if not user:
        return "Someone"
    profile = Profile.objects.filter(user=user).only("display_name").first()
    if profile and profile.display_name:
        return profile.display_name
    return user.first_name or user.email.split("@")[0]


# One builder per action — keeps the "how do I phrase this" decision in one
# place instead of duplicating it across every frontend that consumes this feed.
_ACTIVITY_MESSAGE_BUILDERS = {
    "playlist.created": lambda n, m: f'{n} created a {m.get("visibility", "public")} playlist {m.get("title", "")}',
    "playlist.song_added": lambda n, m: f'{n} added {m.get("song_title", "")} to playlist {m.get("playlist_title", "")}',
    "playlist.song_removed": lambda n, m: f'{n} removed {m.get("song_title", "")} from playlist {m.get("playlist_title", "")}',
    "playlist.song_moved": lambda n, m: f'{n} reordered {m.get("song_title", "")} in playlist {m.get("playlist_title", "")}',
    "playlist.collaborator_invited": lambda n, m: f'{n} invited a collaborator to playlist {m.get("title", "")}',
    "playlist.collaborator_removed": lambda n, m: f'{n} removed a collaborator from playlist {m.get("title", "")}',
    "event.created": lambda n, m: f'{n} created a {m.get("visibility", "public")} room {m.get("title", "")}',
    "event.joined": lambda n, m: (
        f'{n} was invited to the {m.get("visibility", "public")} room {m.get("title", "")}'
        if m.get("via") == "invited"
        else f'{n} joined the {m.get("visibility", "public")} room {m.get("title", "")}'
    ),
    "event.song_added": lambda n, m: f'{n} added {m.get("song_title", "")} to the queue in {m.get("event_title", "")}',
    "event.vote_cast": lambda n, m: f'{n} voted for {m.get("song_title", "")} in {m.get("event_title", "")}',
    "event.vote_retracted": lambda n, m: f'{n} retracted their vote for {m.get("song_title", "")} in {m.get("event_title", "")}',
    "event.guest_invited": lambda n, m: f'{n} invited a guest to room {m.get("title", "")}',
    "event.guest_removed": lambda n, m: f'{n} removed a guest from room {m.get("title", "")}',
}


class ActivityLogSerializer(serializers.ModelSerializer):

    actor_display_name = serializers.SerializerMethodField()
    message = serializers.SerializerMethodField()

    class Meta:
        model = ActionLog
        fields = [
            "id",
            "action",
            "actor_display_name",
            "message",
            "metadata",
            "created_at",
        ]
        read_only_fields = fields

    def get_actor_display_name(self, obj):
        return _actor_display_name(obj.user)

    def get_message(self, obj):
        name = self.get_actor_display_name(obj)
        builder = _ACTIVITY_MESSAGE_BUILDERS.get(obj.action)
        if not builder:
            return f"{name} did something ({obj.action})"
        return builder(name, obj.metadata or {})