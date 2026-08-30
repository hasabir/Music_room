# playlists/serializers.py
from rest_framework import serializers
from .models import Playlist, PlaylistCollaborator, PlaylistSong, PlaylistAccessRequest


class PlaylistSerializer(serializers.ModelSerializer):
    owner = serializers.StringRelatedField(read_only=True)
    song_count = serializers.ReadOnlyField()
    cover_image_url = serializers.SerializerMethodField()

    class Meta:
        model = Playlist
        fields = [
            "id", "owner", "title", "description", "visibility", "edit_permission",
            "cover_image", "cover_preset", "cover_image_url",
            "song_count", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "owner", "song_count", "cover_image_url", "created_at", "updated_at"]
        extra_kwargs = {"cover_image": {"write_only": True}}

    def get_cover_image_url(self, obj):
        return obj.cover_image.url if obj.cover_image else None

    def validate(self, attrs):
        # A playlist shows at most one cover. Uploading an image (this is
        # how `PlaylistDetailView`'s multipart PATCH arrives) always wins
        # over whatever preset was set before.
        if attrs.get("cover_image"):
            attrs["cover_preset"] = ""
        return attrs


class PlaylistCollaboratorSerializer(serializers.ModelSerializer):
    collaborator_email = serializers.EmailField(source="collaborator.email", read_only=True)

    class Meta:
        model = PlaylistCollaborator
        fields = ["id", "playlist", "collaborator", "collaborator_email", "invited_at"]
        read_only_fields = ["id", "invited_at", "collaborator_email"]


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
    added_by_email = serializers.EmailField(source="added_by.email", read_only=True)

    class Meta:
        model = PlaylistSong
        fields = [
            "id", "playlist", "song", "song_external_id", "song_title", "song_artist",
            "song_album_art_url", "song_duration_seconds", "song_preview_url",
            "position", "added_by_email", "added_at",
        ]
        read_only_fields = fields\

class InviteCollaboratorSerializer(serializers.Serializer):
    """Used for POSTing a new collaborator invitation."""
    user_id = serializers.IntegerField()


class PlaylistAccessRequestSerializer(serializers.ModelSerializer):
    requester_email = serializers.EmailField(source="requester.email", read_only=True)

    class Meta:
        model = PlaylistAccessRequest
        fields = ["id", "playlist", "requester", "requester_email", "status", "requested_at", "decided_at"]
        read_only_fields = fields


class DecideAccessRequestSerializer(serializers.Serializer):
    """Used for POSTing an owner's decision on an access request."""
    approve = serializers.BooleanField()
