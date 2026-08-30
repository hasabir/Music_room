# playlists/views_collaborators.py
"""
Endpoints for managing a playlist's collaborator list (used for private
playlists and invited_only edit_permission).

Only the owner can invite/remove collaborators. Owner or any collaborator
can list who's invited.
"""
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse

from authentication.utils import log_action
from user.models import User

from .models import Playlist, PlaylistCollaborator
from .serializers import (
    CollaboratorPermissionsSerializer,
    InviteCollaboratorSerializer,
    PlaylistCollaboratorSerializer,
)
from .permissions import can_user_manage_collaborators
from .broadcast import broadcast_playlist_update


@extend_schema_view(
    get=extend_schema(
        summary="List a playlist's collaborators",
        description="Returns everyone invited to this playlist. Only the owner or an invited collaborator can view this list.",
        responses={200: PlaylistCollaboratorSerializer(many=True)},
        tags=["playlists"],
    ),
    post=extend_schema(
        summary="Invite a collaborator to a playlist",
        description="Invites a user to a private playlist, or grants them edit rights on an invited_only playlist. Owner only.",
        request=InviteCollaboratorSerializer,
        responses={
            201: PlaylistCollaboratorSerializer,
            400: OpenApiResponse(description="User already invited, or inviting yourself."),
            403: OpenApiResponse(description="Only the owner can invite collaborators."),
        },
        tags=["playlists"],
    ),
)
class PlaylistCollaboratorListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, playlist_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)

        is_owner = playlist.owner_id == request.user.id
        is_collaborator = playlist.collaborators.filter(collaborator=request.user).exists()
        if not (is_owner or is_collaborator or playlist.visibility == "public"):
            return Response({"detail": "You do not have access to this playlist."},
                             status=status.HTTP_403_FORBIDDEN)

        collaborators = playlist.collaborators.select_related("collaborator").all()
        return Response(PlaylistCollaboratorSerializer(collaborators, many=True).data)

    def post(self, request, playlist_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)

        if not can_user_manage_collaborators(request.user, playlist):
            return Response({"detail": "You are not allowed to invite collaborators."},
                             status=status.HTTP_403_FORBIDDEN)

        serializer = InviteCollaboratorSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user_id = serializer.validated_data["user_id"]

        if user_id == request.user.id:
            return Response({"detail": "You cannot invite yourself — you're already the owner."},
                             status=status.HTTP_400_BAD_REQUEST)

        invited_user = get_object_or_404(User, id=user_id)

        if PlaylistCollaborator.objects.filter(playlist=playlist, collaborator=invited_user).exists():
            return Response({"detail": "This user is already invited."},
                             status=status.HTTP_400_BAD_REQUEST)

        collaborator = PlaylistCollaborator.objects.create(playlist=playlist, collaborator=invited_user)

        log_action(request, "playlist.collaborator_invited", user=request.user, metadata={
            "playlist_id": playlist.id,
            "title": playlist.title,
            "visibility": playlist.visibility,
            "invited_user_id": invited_user.id,
        })
        broadcast_playlist_update(playlist)

        return Response(PlaylistCollaboratorSerializer(collaborator).data, status=status.HTTP_201_CREATED)


@extend_schema(
    summary="Remove a collaborator from a playlist",
    description="Revokes an invitation / removes a collaborator from the playlist. Owner only.",
    responses={
        204: OpenApiResponse(description="Collaborator removed."),
        403: OpenApiResponse(description="Only the owner can remove collaborators."),
        404: OpenApiResponse(description="This user is not invited to the playlist."),
    },
    tags=["playlists"],
)
class PlaylistCollaboratorRemoveView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, playlist_id, user_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)

        if not can_user_manage_collaborators(request.user, playlist):
            return Response({"detail": "You are not allowed to remove collaborators."},
                             status=status.HTTP_403_FORBIDDEN)

        deleted, _ = PlaylistCollaborator.objects.filter(playlist=playlist, collaborator_id=user_id).delete()
        if not deleted:
            return Response({"detail": "This user is not invited to the playlist."},
                             status=status.HTTP_404_NOT_FOUND)

        log_action(request, "playlist.collaborator_removed", user=request.user, metadata={
            "playlist_id": playlist.id,
            "title": playlist.title,
            "visibility": playlist.visibility,
            "removed_user_id": user_id,
        })
        broadcast_playlist_update(playlist)

        return Response(status=status.HTTP_204_NO_CONTENT)

    def patch(self, request, playlist_id, user_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        if playlist.owner_id != request.user.id:
            return Response(
                {"detail": "Only the owner can change collaborator permissions."},
                status=status.HTTP_403_FORBIDDEN,
            )
        collaborator = get_object_or_404(
            PlaylistCollaborator, playlist=playlist, collaborator_id=user_id
        )
        serializer = CollaboratorPermissionsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        for field, value in serializer.validated_data.items():
            setattr(collaborator, field, value)
        collaborator.save(update_fields=list(serializer.validated_data))
        broadcast_playlist_update(playlist)
        return Response(PlaylistCollaboratorSerializer(collaborator).data)
