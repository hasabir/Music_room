# events/views_guests.py
"""
Endpoints for managing an event's guest list (used for private events
and invited_only vote_permission).

Only the host can invite/remove guests. Any guest (or the host) can
list who's invited.
"""
from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import PermissionDenied

from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse

from authentication.utils import log_action
from user.models import User

from .models import Event, EventGuest
from .serializers import EventGuestSerializer, InviteGuestSerializer


@extend_schema_view(
    get=extend_schema(
        summary="List an event's guests",
        description="Returns everyone invited to this event. Only the host or an invited guest can view this list.",
        responses={200: EventGuestSerializer(many=True)},
        tags=["events"],
    ),
    post=extend_schema(
        summary="Invite a guest to an event",
        description="Invites a user to a private event, or grants them voting rights on an invited_only event. Host only.",
        request=InviteGuestSerializer,
        responses={
            201: EventGuestSerializer,
            400: OpenApiResponse(description="User already invited, or inviting yourself."),
            403: OpenApiResponse(description="Only the host can invite guests."),
        },
        tags=["events"],
    ),
)
class EventGuestListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)

        is_host = event.host_id == request.user.id
        is_guest = event.guests.filter(guest=request.user).exists()
        if not (is_host or is_guest or event.visibility == "public"):
            return Response({"detail": "You do not have access to this event."},
                             status=status.HTTP_403_FORBIDDEN)

        guests = event.guests.select_related("guest").all()
        return Response(EventGuestSerializer(guests, many=True).data)

    def post(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)

        if event.host_id != request.user.id:
            return Response({"detail": "Only the host can invite guests."},
                             status=status.HTTP_403_FORBIDDEN)

        serializer = InviteGuestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user_id = serializer.validated_data["user_id"]

        if user_id == request.user.id:
            return Response({"detail": "You cannot invite yourself — you're already the host."},
                             status=status.HTTP_400_BAD_REQUEST)

        invited_user = get_object_or_404(User, id=user_id)

        if EventGuest.objects.filter(event=event, guest=invited_user).exists():
            return Response({"detail": "This user is already invited."},
                             status=status.HTTP_400_BAD_REQUEST)

        guest = EventGuest.objects.create(event=event, guest=invited_user)

        log_action(request, "event.guest_invited", user=request.user)

        return Response(EventGuestSerializer(guest).data, status=status.HTTP_201_CREATED)


@extend_schema(
    summary="Remove a guest from an event",
    description="Revokes an invitation / removes a guest from the event. Host only.",
    responses={
        204: OpenApiResponse(description="Guest removed."),
        403: OpenApiResponse(description="Only the host can remove guests."),
        404: OpenApiResponse(description="This user is not invited to the event."),
    },
    tags=["events"],
)
class EventGuestRemoveView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, event_id, user_id):
        event = get_object_or_404(Event, id=event_id)

        if event.host_id != request.user.id:
            return Response({"detail": "Only the host can remove guests."},
                             status=status.HTTP_403_FORBIDDEN)

        deleted, _ = EventGuest.objects.filter(event=event, guest_id=user_id).delete()
        if not deleted:
            return Response({"detail": "This user is not invited to the event."},
                             status=status.HTTP_404_NOT_FOUND)

        log_action(request, "event.guest_removed", user=request.user)

        return Response(status=status.HTTP_204_NO_CONTENT)