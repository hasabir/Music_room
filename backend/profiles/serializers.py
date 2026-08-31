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

    username = serializers.CharField(
        source="user.username",
        max_length=30,
        required=False,
        validators=User._meta.get_field("username").validators,
    )

    favorite_genres = serializers.ListField(
        child=serializers.ChoiceField(
            choices=Profile.MUSIC_GENRE_CHOICES
        ),
        required=False,
        allow_empty=True,
    )

    votes_count = serializers.SerializerMethodField()
    playlists_count = serializers.SerializerMethodField()

    # Whichever of `profile_image` / `avatar_external_url` /
    # `avatar_preset_id` is actually active, resolved by `avatar_type` —
    # see `get_avatar`. This is the one thing a client needs to render an
    # avatar without caring which of the three sources set it.
    avatar = serializers.SerializerMethodField()

    class Meta:
        model = Profile
        fields = [
            "id",
            "username",
            "display_name",
            "bio",
            "location",
            "favorite_artist",
            "phone_number",
            "birthday",
            "profile_image",
            "avatar",
            "avatar_type",
            "avatar_preset_id",
            "favorite_genres",
            "field_visibility",
            "votes_count",
            "playlists_count",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "avatar",
            # `avatar_type` is inferred server-side from whichever of
            # `profile_image` / `avatar_preset_id` arrives in a request —
            # see `validate`/`update` — never set directly. In particular
            # a client can never set it to "external_url": that source is
            # only ever assigned server-side at social-sign-in account
            # creation (see `profiles.services.create_profile_for_user`).
            "avatar_type",
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

    def get_avatar(self, obj):
        if obj.avatar_type == "custom":
            return obj.profile_image.url if obj.profile_image else None
        if obj.avatar_type == "external_url":
            return obj.avatar_external_url or None
        return obj.avatar_preset_id or None

    def validate_field_visibility(self, value):
        if not isinstance(value, dict):
            raise serializers.ValidationError("field_visibility must be an object.")

        allowed_fields = {
            "bio", "location", "favorite_artist", "phone_number", "birthday", "activity",
            "favorite_genres",
        }
        allowed_tiers = {tier for tier, _ in Profile.VISIBILITY_CHOICES}

        for field, tier in value.items():
            if field not in allowed_fields:
                raise serializers.ValidationError(f"Unknown field '{field}'.")
            if tier not in allowed_tiers:
                raise serializers.ValidationError(f"Invalid visibility '{tier}' for '{field}'.")

        return value

    def validate_username(self, value):
        username = value.strip()
        if not username:
            raise serializers.ValidationError("Username cannot be empty.")
        if User.objects.filter(username__iexact=username).exclude(
            id=self.instance.user_id if self.instance else None
        ).exists():
            raise serializers.ValidationError("This username is already taken.")
        return username

    def validate(self, attrs):
        # A profile shows exactly one avatar. Uploading a custom image
        # (this is how `MyProfileView`'s multipart PATCH arrives) always
        # wins over whatever preset was picked before — and picking a
        # preset always replaces a previously uploaded custom image.
        # Mirrors `PlaylistSerializer.validate`'s identical
        # cover_image/cover_preset handling.
        if attrs.get("profile_image"):
            attrs["avatar_preset_id"] = ""
        elif attrs.get("avatar_preset_id"):
            attrs["profile_image"] = None
        return attrs

    def update(self, instance, validated_data):
        user_data = validated_data.pop("user", {})
        username = user_data.get("username")
        if username is not None and username != instance.user.username:
            instance.user.username = username
            instance.user.save(update_fields=["username"])
        incoming_visibility = validated_data.pop("field_visibility", None)
        if incoming_visibility is not None:
            instance.field_visibility = {**instance.field_visibility, **incoming_visibility}
        # `avatar_type` isn't client-writable (see Meta.read_only_fields)
        # — it's inferred here from whichever avatar source this request
        # actually touched, then persisted along with everything else by
        # the `super().update()` call below.
        if validated_data.get("profile_image"):
            instance.avatar_type = "custom"
        elif validated_data.get("avatar_preset_id"):
            instance.avatar_type = "preset"
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
