# playlists/views_access_requests.py
"""
Endpoints for requesting access to a playlist you can't currently see
(private) or can't edit (invited_only), and for the owner to decide on
those requests. Approving a request just creates a PlaylistCollaborator,
which already grants both view access and invited_only edit rights.
"""
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse

from authentication.utils import log_action

from .models import Playlist, PlaylistCollaborator, PlaylistAccessRequest
from .serializers import PlaylistAccessRequestSerializer, DecideAccessRequestSerializer
from .throttles import AccessRequestRateThrottle
from .broadcast import broadcast_playlist_update


@extend_schema_view(
    get=extend_schema(
        summary="List access requests for a playlist",
        description="Returns every access request made for this playlist. Owner only.",
        responses={200: PlaylistAccessRequestSerializer(many=True)},
        tags=["playlists"],
    ),
    post=extend_schema(
        summary="Request access to a playlist",
        description=(
            "Asks the owner for collaborator access — lets you view a private "
            "playlist, or edit an invited_only one. Returns the existing "
            "pending request if you already have one."
        ),
        responses={
            201: PlaylistAccessRequestSerializer,
            200: PlaylistAccessRequestSerializer,
            400: OpenApiResponse(description="You already have access to this playlist."),
        },
        tags=["playlists"],
    ),
)
class PlaylistAccessRequestListCreateView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [AccessRequestRateThrottle]

    def get(self, request, playlist_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        if playlist.owner_id != request.user.id:
            return Response({"detail": "Only the owner can view access requests."},
                             status=status.HTTP_403_FORBIDDEN)

        requests = playlist.access_requests.select_related("requester").all()
        return Response(PlaylistAccessRequestSerializer(requests, many=True).data)

    def post(self, request, playlist_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)

        if playlist.owner_id == request.user.id:
            return Response({"detail": "You already own this playlist."},
                             status=status.HTTP_400_BAD_REQUEST)

        if playlist.collaborators.filter(collaborator=request.user).exists():
            return Response({"detail": "You already have access to this playlist."},
                             status=status.HTTP_400_BAD_REQUEST)

        existing = playlist.access_requests.filter(
            requester=request.user, status=PlaylistAccessRequest.STATUS_PENDING
        ).first()
        if existing:
            return Response(PlaylistAccessRequestSerializer(existing).data, status=status.HTTP_200_OK)

        access_request = PlaylistAccessRequest.objects.create(playlist=playlist, requester=request.user)

        log_action(request, "playlist.access_requested", user=request.user, metadata={
            "playlist_id": playlist.id,
            "title": playlist.title,
        })

        return Response(PlaylistAccessRequestSerializer(access_request).data, status=status.HTTP_201_CREATED)


@extend_schema_view(
    get=extend_schema(
        summary="Get my access request status for a playlist",
        description="Returns the signed-in user's most recent access request for this playlist.",
        responses={
            200: PlaylistAccessRequestSerializer,
            404: OpenApiResponse(description="No access request from you exists for this playlist."),
        },
        tags=["playlists"],
    ),
    delete=extend_schema(
        summary="Cancel my pending playlist access request",
        description="Cancels the signed-in user's pending request, if one exists.",
        responses={
            204: None,
            404: OpenApiResponse(description="No pending access request from you exists for this playlist."),
        },
        tags=["playlists"],
    ),
)
class PlaylistAccessRequestMineView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, playlist_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        access_request = playlist.access_requests.filter(requester=request.user).first()
        if not access_request:
            return Response({"detail": "No access request found."}, status=status.HTTP_404_NOT_FOUND)
        return Response(PlaylistAccessRequestSerializer(access_request).data)

    def delete(self, request, playlist_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        access_request = playlist.access_requests.filter(
            requester=request.user,
            status=PlaylistAccessRequest.STATUS_PENDING,
        ).first()
        if not access_request:
            return Response(
                {"detail": "No pending access request found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        access_request.delete()
        log_action(request, "playlist.access_request_cancelled", user=request.user, metadata={
            "playlist_id": playlist.id,
            "title": playlist.title,
        })
        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(
    summary="Approve or deny an access request",
    description="Approving adds the requester as a collaborator. Owner only.",
    request=DecideAccessRequestSerializer,
    responses={
        200: PlaylistAccessRequestSerializer,
        400: OpenApiResponse(description="This request has already been decided."),
        403: OpenApiResponse(description="Only the owner can decide access requests."),
    },
    tags=["playlists"],
)
class PlaylistAccessRequestDecideView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, playlist_id, request_id):
        playlist = get_object_or_404(Playlist, id=playlist_id)
        if playlist.owner_id != request.user.id:
            return Response({"detail": "Only the owner can decide access requests."},
                             status=status.HTTP_403_FORBIDDEN)

        access_request = get_object_or_404(PlaylistAccessRequest, id=request_id, playlist=playlist)
        if access_request.status != PlaylistAccessRequest.STATUS_PENDING:
            return Response({"detail": "This request has already been decided."},
                             status=status.HTTP_400_BAD_REQUEST)

        serializer = DecideAccessRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        approve = serializer.validated_data["approve"]

        access_request.status = (
            PlaylistAccessRequest.STATUS_APPROVED if approve else PlaylistAccessRequest.STATUS_DENIED
        )
        access_request.decided_at = timezone.now()
        access_request.save(update_fields=["status", "decided_at"])

        if approve:
            PlaylistCollaborator.objects.get_or_create(
                playlist=playlist, collaborator=access_request.requester
            )

        log_action(request, "playlist.access_request_decided", user=request.user, metadata={
            "playlist_id": playlist.id,
            "title": playlist.title,
            "requester_id": access_request.requester_id,
            "approved": approve,
        })
        broadcast_playlist_update(playlist)

        return Response(PlaylistAccessRequestSerializer(access_request).data)
