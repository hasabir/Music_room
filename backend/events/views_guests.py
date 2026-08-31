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

from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse, OpenApiParameter

from authentication.utils import log_action
from user.models import User

from .models import Event, EventGuest, EventMembership
from .serializers import EventGuestSerializer, InviteGuestSerializer, EventMembershipSerializer
from .permissions import can_user_see_event


@extend_schema_view(
    get=extend_schema(
        summary="List an event's guests",
        description=(
            "Returns everyone invited to this event. Only the host, an "
            "invited guest, or anyone if the event is public can view "
            "this list. Optionally filter by `?status=pending|accepted|"
            "declined` (rsvp_status) — omit it to get everyone regardless "
            "of status, as before."
        ),
        parameters=[
            OpenApiParameter(
                name="status", type=str, required=False,
                description="Filter by rsvp_status: pending, accepted, or declined.",
            ),
        ],
        responses={
            200: EventGuestSerializer(many=True),
            400: OpenApiResponse(description="Invalid status filter."),
        },
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

        status_filter = request.query_params.get("status")
        if status_filter is not None:
            valid_statuses = dict(EventGuest.RSVP_STATUS_CHOICES)
            if status_filter not in valid_statuses:
                return Response({"detail": "Invalid status filter."},
                                 status=status.HTTP_400_BAD_REQUEST)
            guests = guests.filter(rsvp_status=status_filter)

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

        log_action(request, "event.guest_invited", user=request.user, metadata={
            "event_id": event.id,
            "title": event.title,
            "visibility": event.visibility,
            "invited_user_id": invited_user.id,
        })
        # Also surface this on the invited guest's own activity feed —
        # from their side, being added to a private event reads as "joined".
        log_action(request, "event.joined", user=invited_user, metadata={
            "event_id": event.id,
            "title": event.title,
            "visibility": event.visibility,
            "via": "invited",
        })

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

        log_action(request, "event.guest_removed", user=request.user, metadata={
            "event_id": event.id,
            "title": event.title,
            "visibility": event.visibility,
            "removed_user_id": user_id,
        })

        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(
    summary="Respond to your own invitation",
    description=(
        "Sets the signed-in user's own RSVP status on their EventGuest "
        "invitation for this event — accept or decline. Only callable by "
        "the invited user themselves, on their own invitation; changing "
        "an existing response (e.g. accepted -> declined) is allowed, not "
        "just a one-time first response."
    ),
    request={
        "application/json": {
            "type": "object",
            "properties": {
                "response": {"type": "string", "enum": ["accepted", "declined"]},
            },
        }
    },
    responses={
        200: EventGuestSerializer,
        400: OpenApiResponse(description="Response must be 'accepted' or 'declined'."),
        404: OpenApiResponse(description="You have not been invited to this event."),
    },
    tags=["events"],
)
class EventGuestRespondView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)

        response_value = request.data.get("response")
        if response_value not in (EventGuest.RSVP_ACCEPTED, EventGuest.RSVP_DECLINED):
            return Response({"detail": "Response must be 'accepted' or 'declined'."},
                             status=status.HTTP_400_BAD_REQUEST)

        guest = EventGuest.objects.filter(event=event, guest=request.user).first()
        if not guest:
            return Response({"detail": "You have not been invited to this event."},
                             status=status.HTTP_404_NOT_FOUND)

        guest.rsvp_status = response_value
        guest.save(update_fields=["rsvp_status"])

        log_action(request, f"event.guest_{response_value}", user=request.user, metadata={
            "event_id": event.id,
            "title": event.title,
            "visibility": event.visibility,
        })

        return Response(EventGuestSerializer(guest).data, status=status.HTTP_200_OK)


@extend_schema(
    summary="Join a public room",
    description=(
        "Self-serve join for a public event/room — any authenticated user "
        "can join. Private events cannot be self-joined; the host must "
        "invite you (see `POST /events/<id>/guests/`).\n\n"
        "This only records that you've joined the room for activity/"
        "membership purposes — it does not grant `invited_only` voting "
        "rights, which remain host-controlled via the guest list."
    ),
    responses={
        201: EventMembershipSerializer,
        400: OpenApiResponse(description="Already joined, or you're the host."),
        403: OpenApiResponse(description="This event is private — you must be invited."),
    },
    tags=["events"],
)
class EventJoinView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)

        if event.host_id == request.user.id:
            return Response({"detail": "You are the host of this event."},
                             status=status.HTTP_400_BAD_REQUEST)

        if event.visibility != "public":
            return Response({"detail": "This event is private — you must be invited by the host."},
                             status=status.HTTP_403_FORBIDDEN)

        membership, created = EventMembership.objects.get_or_create(event=event, member=request.user)
        if not created:
            return Response({"detail": "You have already joined this event."},
                             status=status.HTTP_400_BAD_REQUEST)

        log_action(request, "event.joined", user=request.user, metadata={
            "event_id": event.id,
            "title": event.title,
            "visibility": event.visibility,
            "via": "joined",
        })

        return Response(EventMembershipSerializer(membership).data, status=status.HTTP_201_CREATED)


@extend_schema(
    summary="List an event's attendees",
    description=(
        "Returns everyone who has self-joined this event via POST "
        ".../join/ (EventMembership rows) — the 'attendee' list, distinct "
        "from the guest/collaborator list above. Same visibility rule as "
        "the guest list: host, invited guest, or anyone if the event is "
        "public. Attendees are currently public-events-only (no "
        "EventMembership is created for a private event's invited "
        "guests), so a private event simply returns an empty list here "
        "rather than erroring."
    ),
    responses={
        200: EventMembershipSerializer(many=True),
        403: OpenApiResponse(description="You do not have access to this event."),
    },
    tags=["events"],
)
class EventAttendeeListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)
        if not can_user_see_event(request.user, event):
            return Response({"detail": "You do not have access to this event."},
                             status=status.HTTP_403_FORBIDDEN)

        attendees = event.members.select_related("member").all()
        return Response(EventMembershipSerializer(attendees, many=True).data)