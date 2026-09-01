# playlists/serializers.py
from rest_framework import serializers
from profiles.serializers import _actor_display_name
from profiles.services import avatar_for_user
from .models import Playlist, PlaylistCollaborator, PlaylistSong, PlaylistAccessRequest


class PlaylistSerializer(serializers.ModelSerializer):
    owner = serializers.StringRelatedField(read_only=True)
    song_count = serializers.ReadOnlyField()
    cover_image_url = serializers.SerializerMethodField()
    is_collaborator = serializers.SerializerMethodField()

    class Meta:
        model = Playlist
        fields = [
            "id", "owner", "title", "description", "visibility", "edit_permission",
            "cover_image", "cover_preset", "cover_image_url",
            "song_count", "is_collaborator", "created_at", "updated_at",
        ]
        read_only_fields = [
            "id", "owner", "song_count", "cover_image_url", "is_collaborator", "created_at", "updated_at",
        ]
        extra_kwargs = {"cover_image": {"write_only": True}}

    def get_cover_image_url(self, obj):
        return obj.cover_image.url if obj.cover_image else None

    def get_is_collaborator(self, obj):
        """Whether the signed-in user is an invited `PlaylistCollaborator`
        on this playlist — distinct from owning it. Unlike events, there's
        no self-serve "join" for playlists; collaborator access always
        comes from an owner invite or an approved access request. Lets the
        client tell a public playlist the user already collaborates on
        apart from one they've merely discovered."""
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return False
        return obj.collaborators.filter(collaborator=request.user).exists()

    def validate(self, attrs):
        # A playlist shows at most one cover. Uploading an image (this is
        # how `PlaylistDetailView`'s multipart PATCH arrives) always wins
        # over whatever preset was set before.
        if attrs.get("cover_image"):
            attrs["cover_preset"] = ""
        elif "cover_preset" in attrs:
            # Choosing a built-in look replaces any previously uploaded photo.
            attrs["cover_image"] = None
        return attrs


class PlaylistCollaboratorSerializer(serializers.ModelSerializer):
    collaborator_username = serializers.CharField(source="collaborator.username", read_only=True)
    collaborator_display_name = serializers.SerializerMethodField()
    collaborator_avatar = serializers.SerializerMethodField()
    collaborator_avatar_type = serializers.SerializerMethodField()

    class Meta:
        model = PlaylistCollaborator
        fields = [
            "id", "playlist", "collaborator", "collaborator_username", "collaborator_display_name",
            "collaborator_avatar", "collaborator_avatar_type", "invited_at",
            "can_add_songs", "can_reorder_songs", "can_manage_collaborators",
        ]
        read_only_fields = [
            "id", "invited_at", "collaborator_username", "collaborator_display_name",
            "collaborator_avatar", "collaborator_avatar_type",
        ]

    def get_collaborator_display_name(self, obj):
        return _actor_display_name(obj.collaborator)

    def get_collaborator_avatar(self, obj):
        return avatar_for_user(obj.collaborator)[0]

    def get_collaborator_avatar_type(self, obj):
        return avatar_for_user(obj.collaborator)[1]


class AddSongToPlaylistSerializer(serializers.Serializer):
    """Used for POSTing a new song into a playlist (creates events.Song + PlaylistSong together)."""
    title = serializers.CharField(max_length=200)
    artist = serializers.CharField(max_length=200)
    duration_seconds = serializers.IntegerField(required=False, allow_null=True)
    external_id = serializers.CharField(max_length=100, required=False, allow_blank=True)
    album_art_url = serializers.URLField(max_length=500, required=False, allow_blank=True)
    preview_url = serializers.URLField(max_length=500, required=False, allow_blank=True)


class MoveSongSerializer(serializers.Serializer):
    """Used for reordering: where should this song move to?"""
    new_position = serializers.IntegerField(min_value=0)


class PlaylistSongSerializer(serializers.ModelSerializer):
    song_external_id = serializers.CharField(source="song.external_id", read_only=True)
    song_title = serializers.CharField(source="song.title", read_only=True)
    song_artist = serializers.CharField(source="song.artist", read_only=True)
    song_album_art_url = serializers.CharField(source="song.album_art_url", read_only=True)
    song_duration_seconds = serializers.IntegerField(source="song.duration_seconds", read_only=True)
    song_preview_url = serializers.CharField(source="song.preview_url", read_only=True)
    added_by_username = serializers.CharField(source="added_by.username", read_only=True)

    class Meta:
        model = PlaylistSong
        fields = [
            "id", "playlist", "song", "song_external_id", "song_title", "song_artist",
            "song_album_art_url", "song_duration_seconds", "song_preview_url",
            "position", "added_by_username", "added_at",
        ]
        read_only_fields = fields\

class InviteCollaboratorSerializer(serializers.Serializer):
    """Used for POSTing a new collaborator invitation."""
    user_id = serializers.IntegerField()


class CollaboratorPermissionsSerializer(serializers.Serializer):
    can_add_songs = serializers.BooleanField()
    can_reorder_songs = serializers.BooleanField()
    can_manage_collaborators = serializers.BooleanField()


class PlaylistAccessRequestSerializer(serializers.ModelSerializer):
    requester_username = serializers.CharField(source="requester.username", read_only=True)
    requester_display_name = serializers.SerializerMethodField()
    requester_avatar = serializers.SerializerMethodField()
    requester_avatar_type = serializers.SerializerMethodField()

    class Meta:
        model = PlaylistAccessRequest
        fields = [
            "id", "playlist", "requester", "requester_username", "requester_display_name",
            "requester_avatar", "requester_avatar_type", "status", "requested_at", "decided_at",
        ]
        read_only_fields = fields

    def get_requester_display_name(self, obj):
        return _actor_display_name(obj.requester)

    def get_requester_avatar(self, obj):
        return avatar_for_user(obj.requester)[0]

    def get_requester_avatar_type(self, obj):
        return avatar_for_user(obj.requester)[1]


class DecideAccessRequestSerializer(serializers.Serializer):
    """Used for POSTing an owner's decision on an access request."""
    approve = serializers.BooleanField()
