# playlists/views.py
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import PermissionDenied
from .throttles import AddPlaylistSongRateThrottle, MoveSongRateThrottle, CreatePlaylistRateThrottle
from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse

from authentication.utils import log_action
from events.models import Song

from .models import Playlist, PlaylistSong
from .serializers import (
    PlaylistSerializer, AddSongToPlaylistSerializer, MoveSongSerializer, PlaylistSongSerializer
)
from .permissions import can_user_see_playlist, can_user_edit_playlist
from .services import add_song_to_playlist, remove_song_from_playlist, move_song
from .broadcast import broadcast_playlist_update


@extend_schema_view(
    get=extend_schema(
        summary="List my playlists",
        description="Returns all public playlists, plus private playlists you own or are invited to.",
        responses={200: PlaylistSerializer(many=True)},
        tags=["playlists"],
    ),
    post=extend_schema(
        summary="Create a playlist",
        description="Creates a new playlist. The logged-in user automatically becomes the owner.",
        request=PlaylistSerializer,
        responses={201: PlaylistSerializer},
        tags=["playlists"],
    ),
)
class PlaylistListCreateView(generics.ListCreateAPIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [CreatePlaylistRateThrottle]
    serializer_class = PlaylistSerializer

    def get_queryset(self):
        user = self.request.user
        return Playlist.objects.filter(
            Q(visibility="public") | Q(owner=user) | Q(collaborators__collaborator=user)
        ).distinct()

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)
        log_action(self.request, "playlist.created", user=self.request.user)


@extend_schema_view(
    get=extend_schema(
        summary="Get playlist details",
        responses={200: PlaylistSerializer},
        tags=["playlists"],
    ),
    put=extend_schema(
        summary="Update a playlist (owner only)",
        request=PlaylistSerializer,
        responses={200: PlaylistSerializer},
        tags=["playlists"],
    ),
    patch=extend_schema(
        summary="Partially update a playlist (owner only)",
        request=PlaylistSerializer,
        responses={200: PlaylistSerializer},
        tags=["playlists"],
    ),
    delete=extend_schema(
        summary="Delete a playlist (owner only)",
        responses={204: OpenApiResponse(description="Playlist deleted.")},
        tags=["playlists"],
    ),
)
class PlaylistDetailView(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = PlaylistSerializer
    queryset = Playlist.objects.all()

    def get_object(self):
        playlist = super().get_object()
        if not can_user_see_playlist(self.request.user, playlist):
            raise PermissionDenied("You do not have access to this playlist.")
        return playlist

    def perform_update(self, serializer):
        if serializer.instance.owner_id != self.request.user.id:
            raise PermissionDenied("Only the owner can edit this playlist.")
        serializer.save()

    def perform_destroy(self, instance):
        if instance.owner_id != self.request.user.id:
            raise PermissionDenied("Only the owner can delete this playlist.")
        instance.delete()


@extend_schema_view(
    get=extend_schema(
        summary="List songs in the playlist",
        description="Returns all songs in this playlist, in order.",
        responses={200: PlaylistSongSerializer(many=True)},
        tags=["playlists"],
    ),
    post=extend_schema(
        summary="Add a song to the playlist",
        description=(
            "Adds a new song to the end of the playlist. Reuses an "
            "existing catalog song if the same title/artist already "
            "exists. Fails if the song is already in this playlist."
        ),
        request=AddSongToPlaylistSerializer,
        responses={
            201: PlaylistSongSerializer,
            400: OpenApiResponse(description="Song already in playlist, or invalid input."),
            403: OpenApiResponse(description="Not allowed to edit this playlist."),
        },
        tags=["playlists"],
    ),
)
class PlaylistSongListView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [AddPlaylistSongRateThrottle]
    def get(self, request, playlist_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        if not can_user_see_playlist(request.user, playlist):
            return Response({"detail": "You do not have access to this playlist."},
                             status=status.HTTP_403_FORBIDDEN)

        songs = playlist.songs.all()  # already ordered by position via Meta.ordering
        return Response(PlaylistSongSerializer(songs, many=True).data)

    def post(self, request, playlist_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        allowed, reason = can_user_edit_playlist(request.user, playlist)
        if not allowed:
            return Response({"detail": reason}, status=status.HTTP_403_FORBIDDEN)

        serializer = AddSongToPlaylistSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        song, _ = Song.objects.get_or_create(
            title__iexact=data["title"],
            artist__iexact=data["artist"],
            defaults={
                "title": data["title"],
                "artist": data["artist"],
                "duration_seconds": data.get("duration_seconds"),
                "external_id": data.get("external_id", ""),
            },
        )

        if PlaylistSong.objects.filter(playlist=playlist, song=song).exists():
            return Response({"detail": "This song is already in the playlist."},
                             status=status.HTTP_400_BAD_REQUEST)

        playlist_song = add_song_to_playlist(playlist, song, request.user)

        log_action(request, "playlist.song_added", user=request.user)
        broadcast_playlist_update(playlist)

        return Response(PlaylistSongSerializer(playlist_song).data, status=status.HTTP_201_CREATED)


@extend_schema(
    summary="Remove a song from the playlist",
    description=(
        "Removes a song from the playlist. Positions of all songs after "
        "it automatically shift down to close the gap."
    ),
    responses={
        204: OpenApiResponse(description="Song removed."),
        403: OpenApiResponse(description="Not allowed to edit this playlist."),
        404: OpenApiResponse(description="Song not found in this playlist."),
    },
    tags=["playlists"],
)
class PlaylistSongDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, playlist_id, playlist_song_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        allowed, reason = can_user_edit_playlist(request.user, playlist)
        if not allowed:
            return Response({"detail": reason}, status=status.HTTP_403_FORBIDDEN)

        removed = remove_song_from_playlist(playlist, playlist_song_id)
        if not removed:
            return Response({"detail": "Song not found in this playlist."},
                             status=status.HTTP_404_NOT_FOUND)

        log_action(request, "playlist.song_removed", user=request.user)
        broadcast_playlist_update(playlist)

        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(
    summary="Move a song to a new position",
    description=(
        "Reorders the playlist by moving one song to `new_position`. "
        "Every song in between shifts to make room. Runs inside a "
        "database transaction with row locking, so simultaneous moves "
        "from different users cannot corrupt the order."
    ),
    request=MoveSongSerializer,
    responses={
        200: PlaylistSongSerializer,
        403: OpenApiResponse(description="Not allowed to edit this playlist."),
        404: OpenApiResponse(description="Song not found in this playlist."),
    },
    tags=["playlists"],
)
class PlaylistSongMoveView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [MoveSongRateThrottle] 
    def post(self, request, playlist_id, playlist_song_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        allowed, reason = can_user_edit_playlist(request.user, playlist)
        if not allowed:
            return Response({"detail": reason}, status=status.HTTP_403_FORBIDDEN)

        serializer = MoveSongSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        new_position = serializer.validated_data["new_position"]

        updated = move_song(playlist, playlist_song_id, new_position)
        if not updated:
            return Response({"detail": "Song not found in this playlist."},
                             status=status.HTTP_404_NOT_FOUND)

        log_action(request, "playlist.song_moved", user=request.user)
        broadcast_playlist_update(playlist)

        return Response(PlaylistSongSerializer(updated).data, status=status.HTTP_200_OK)