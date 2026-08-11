# playlists/serializers.py
from rest_framework import serializers
from .models import Playlist, PlaylistCollaborator, PlaylistSong


class PlaylistSerializer(serializers.ModelSerializer):
    owner = serializers.StringRelatedField(read_only=True)
    song_count = serializers.ReadOnlyField()

    class Meta:
        model = Playlist
        fields = [
            "id", "owner", "title", "visibility", "edit_permission",
            "song_count", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "owner", "song_count", "created_at", "updated_at"]


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


class MoveSongSerializer(serializers.Serializer):
    """Used for reordering: where should this song move to?"""
    new_position = serializers.IntegerField(min_value=0)


class PlaylistSongSerializer(serializers.ModelSerializer):
    song_title = serializers.CharField(source="song.title", read_only=True)
    song_artist = serializers.CharField(source="song.artist", read_only=True)
    added_by_email = serializers.EmailField(source="added_by.email", read_only=True)

    class Meta:
        model = PlaylistSong
        fields = [
            "id", "playlist", "song", "song_title", "song_artist",
            "position", "added_by_email", "added_at",
        ]
        read_only_fields = fields