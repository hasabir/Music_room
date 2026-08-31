# events/views_access_requests.py
"""
Endpoints for requesting access to a private event you can't currently
see, and for the host to decide on those requests. Approving a request
just creates an EventGuest, which already grants both private-event
visibility and invited_only voting rights. Mirrors
playlists/views_access_requests.py, adapted to Events' host/guest model.
"""
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse

from authentication.utils import log_action

from .models import Event, EventGuest, EventAccessRequest
from .serializers import EventAccessRequestSerializer, DecideAccessRequestSerializer
from .throttles import AccessRequestRateThrottle
from .broadcast import broadcast_queue_update


@extend_schema_view(
    get=extend_schema(
        summary="List access requests for an event",
        description="Returns every access request made for this event. Host only.",
        responses={200: EventAccessRequestSerializer(many=True)},
        tags=["events"],
    ),
    post=extend_schema(
        summary="Request access to a private event",
        description=(
            "Asks the host for guest access — lets you view a private event "
            "and vote if vote_permission is invited_only. Public events "
            "cannot be requested this way; use POST /events/<id>/join/ "
            "instead. Returns the existing pending request if you already "
            "have one."
        ),
        responses={
            201: EventAccessRequestSerializer,
            200: EventAccessRequestSerializer,
            400: OpenApiResponse(description="You already own/have access to this event, or it's public."),
        },
        tags=["events"],
    ),
)
class EventAccessRequestListCreateView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [AccessRequestRateThrottle]

    def get(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)
        if event.host_id != request.user.id:
            return Response({"detail": "Only the host can view access requests."},
                             status=status.HTTP_403_FORBIDDEN)

        requests = event.access_requests.select_related("requester").all()
        return Response(EventAccessRequestSerializer(requests, many=True).data)

    def post(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)

        if event.host_id == request.user.id:
            return Response({"detail": "You already own this event."},
                             status=status.HTTP_400_BAD_REQUEST)

        if event.guests.filter(guest=request.user).exists():
            return Response({"detail": "You already have access to this event."},
                             status=status.HTTP_400_BAD_REQUEST)

        existing = event.access_requests.filter(
            requester=request.user, status=EventAccessRequest.STATUS_PENDING
        ).first()
        if existing:
            return Response(EventAccessRequestSerializer(existing).data, status=status.HTTP_200_OK)

        if event.visibility != "private":
            return Response(
                {"detail": "This event is public — join it directly instead of requesting access."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        access_request = EventAccessRequest.objects.create(event=event, requester=request.user)

        log_action(request, "event.access_requested", user=request.user, metadata={
            "event_id": event.id,
            "title": event.title,
        })

        return Response(EventAccessRequestSerializer(access_request).data, status=status.HTTP_201_CREATED)


@extend_schema_view(
    get=extend_schema(
        summary="Get my access request status for an event",
        description="Returns the signed-in user's most recent access request for this event.",
        responses={
            200: EventAccessRequestSerializer,
            404: OpenApiResponse(description="No access request from you exists for this event."),
        },
        tags=["events"],
    ),
    delete=extend_schema(
        summary="Cancel my pending event access request",
        description="Cancels the signed-in user's pending request, if one exists.",
        responses={
            204: None,
            404: OpenApiResponse(description="No pending access request from you exists for this event."),
        },
        tags=["events"],
    ),
)
class EventAccessRequestMineView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)
        access_request = event.access_requests.filter(requester=request.user).first()
        if not access_request:
            return Response({"detail": "No access request found."}, status=status.HTTP_404_NOT_FOUND)
        return Response(EventAccessRequestSerializer(access_request).data)

    def delete(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)
        access_request = event.access_requests.filter(
            requester=request.user,
            status=EventAccessRequest.STATUS_PENDING,
        ).first()
        if not access_request:
            return Response(
                {"detail": "No pending access request found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        access_request.delete()
        log_action(request, "event.access_request_cancelled", user=request.user, metadata={
            "event_id": event.id,
            "title": event.title,
        })
        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(
    summary="Approve or deny an access request",
    description="Approving adds the requester as a guest. Host only.",
    request=DecideAccessRequestSerializer,
    responses={
        200: EventAccessRequestSerializer,
        400: OpenApiResponse(description="This request has already been decided."),
        403: OpenApiResponse(description="Only the host can decide access requests."),
    },
    tags=["events"],
)
class EventAccessRequestDecideView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, event_id, request_id):
        event = get_object_or_404(Event, id=event_id)
        if event.host_id != request.user.id:
            return Response({"detail": "Only the host can decide access requests."},
                             status=status.HTTP_403_FORBIDDEN)

        access_request = get_object_or_404(EventAccessRequest, id=request_id, event=event)
        if access_request.status != EventAccessRequest.STATUS_PENDING:
            return Response({"detail": "This request has already been decided."},
                             status=status.HTTP_400_BAD_REQUEST)

        serializer = DecideAccessRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        approve = serializer.validated_data["approve"]

        access_request.status = (
            EventAccessRequest.STATUS_APPROVED if approve else EventAccessRequest.STATUS_DENIED
        )
        access_request.decided_at = timezone.now()
        access_request.save(update_fields=["status", "decided_at"])

        if approve:
            EventGuest.objects.get_or_create(event=event, guest=access_request.requester)
            # Guest list changed — let anyone already watching this event's
            # queue know (mirrors how playlist access-request decisions
            # broadcast the refreshed collaborator list).
            broadcast_queue_update(event)

        log_action(request, "event.access_request_decided", user=request.user, metadata={
            "event_id": event.id,
            "title": event.title,
            "requester_id": access_request.requester_id,
            "approved": approve,
        })

        return Response(EventAccessRequestSerializer(access_request).data)
