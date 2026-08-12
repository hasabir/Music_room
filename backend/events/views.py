# events/views.py
from django.db import IntegrityError , transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import PermissionDenied
from .throttles import VoteRateThrottle, AddSongRateThrottle, CreateEventRateThrottle
from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse
from authentication.utils import log_action

from .models import Event, Song, EventSong, Vote
from .serializers import (
    EventSerializer, AddSongToQueueSerializer, EventSongSerializer
)
from .permissions import can_user_see_event, can_user_vote
from .broadcast import broadcast_queue_update

@extend_schema_view(
    get=extend_schema(
        summary="List my events",
        description=(
            "Returns all public events, plus private events you host "
            "or have been invited to."
        ),
        responses={200: EventSerializer(many=True)},
        tags=["events"],
    ),
    post=extend_schema(
        summary="Create an event",
        description=(
            "Creates a new event. The logged-in user automatically "
            "becomes the host. Set `vote_permission` to "
            "`location_time_restricted` to require venue coordinates "
            "and a voting time window."
        ),
        request=EventSerializer,
        responses={201: EventSerializer},
        tags=["events"],
    ),
)
class EventListCreateView(generics.ListCreateAPIView):
    """
    GET  -> list events the current user can see
            (public events + private events they host or are invited to)
    POST -> create a new event (current user becomes the host)
    """
    permission_classes = [IsAuthenticated]
    throttle_classes = [CreateEventRateThrottle] 
    serializer_class = EventSerializer

    def get_queryset(self):
        user = self.request.user
        return Event.objects.filter(
            Q(visibility="public") | Q(host=user) | Q(guests__guest=user)
        ).distinct()

    def perform_create(self, serializer):
        serializer.save(host=self.request.user)
        log_action(self.request, "event.created", user=self.request.user)


@extend_schema_view(
    get=extend_schema(
        summary="Get event details",
        description="Returns full details of one event. You must be able to see the event (public, host, or invited guest).",
        responses={200: EventSerializer},
        tags=["events"],
    ),
    put=extend_schema(
        summary="Update an event (host only)",
        description="Full update of an event. Only the host can perform this action.",
        request=EventSerializer,
        responses={200: EventSerializer},
        tags=["events"],
    ),
    patch=extend_schema(
        summary="Partially update an event (host only)",
        description="Update one or more fields of an event without resending the whole object. Only the host can perform this action.",
        request=EventSerializer,
        responses={200: EventSerializer},
        tags=["events"],
    ),
    delete=extend_schema(
        summary="Delete an event (host only)",
        description="Permanently deletes the event and its entire queue/votes. Only the host can perform this action.",
        responses={204: OpenApiResponse(description="Event deleted.")},
        tags=["events"],
    ),
)
class EventDetailView(generics.RetrieveUpdateDestroyAPIView):
    """View, update, or delete a single event. Only the host can update/delete."""
    permission_classes = [IsAuthenticated]
    serializer_class = EventSerializer
    queryset = Event.objects.all()

    def get_object(self):
        event = super().get_object()
        if not can_user_see_event(self.request.user, event):
            raise PermissionDenied("You do not have access to this event.")
        return event

    def perform_update(self, serializer):
        if serializer.instance.host_id != self.request.user.id:
            raise PermissionDenied("Only the host can edit this event.")
        serializer.save()

    def perform_destroy(self, instance):
        if instance.host_id != self.request.user.id:
            raise PermissionDenied("Only the host can delete this event.")
        instance.delete()


@extend_schema_view(
    get=extend_schema(
        summary="List the song queue",
        description=(
            "Returns all songs in this event's queue, sorted by vote "
            "count (most-voted first). This is the ranked list that "
            "determines what plays next."
        ),
        responses={
            200: EventSongSerializer(many=True),
            403: OpenApiResponse(description="You do not have access to this event."),
        },
        tags=["events"],
    ),
    post=extend_schema(
        summary="Add a song to the queue",
        description=(
            "Adds a new song to this event's queue. If a song with the "
            "same title and artist already exists in the catalog, it "
            "is reused instead of creating a duplicate. Fails if the "
            "song is already in this event's queue."
        ),
        request=AddSongToQueueSerializer,
        responses={
            201: EventSongSerializer,
            400: OpenApiResponse(description="Song already in queue, or invalid input."),
            403: OpenApiResponse(description="You do not have access to this event."),
        },
        tags=["events"],
    ),
)
class EventQueueView(APIView):
    """
    GET  -> list the event's song queue, sorted by vote count (most-voted first)
    POST -> add a new song to the event's queue
    """
    permission_classes = [IsAuthenticated]
    throttle_classes = [AddSongRateThrottle] 
    def get(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)
        if not can_user_see_event(request.user, event):
            return Response({"detail": "You do not have access to this event."},
                             status=status.HTTP_403_FORBIDDEN)

        queue = sorted(event.queue.all(), key=lambda es: es.vote_count, reverse=True)
        serializer = EventSongSerializer(queue, many=True, context={"request": request})
        return Response(serializer.data)

    def post(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)
        if not can_user_see_event(request.user, event):
            return Response({"detail": "You do not have access to this event."},
                             status=status.HTTP_403_FORBIDDEN)

        serializer = AddSongToQueueSerializer(data=request.data)
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

        event_song, created = EventSong.objects.get_or_create(
            event=event, song=song, defaults={"added_by": request.user}
        )
        if not created:
            return Response({"detail": "This song is already in the queue."},
                             status=status.HTTP_400_BAD_REQUEST)

        log_action(request, "event.song_added", user=request.user)
        broadcast_queue_update(event)  
        return Response(
            EventSongSerializer(event_song, context={"request": request}).data,
            status=status.HTTP_201_CREATED
        )


@extend_schema_view(
    post=extend_schema(
        summary="Vote for a song",
        description=(
            "Casts a vote for a song in this event's queue. Requires "
            "at least 2 songs in the queue. Access depends on the "
            "event's `vote_permission` setting:\n\n"
            "- `everyone`: any user who can see the event can vote.\n"
            "- `invited_only`: only the host and invited guests can vote.\n"
            "- `location_time_restricted`: requires `latitude`/`longitude` "
            "in the request body, and the current time must be within "
            "the event's voting window."
        ),
        request={
            "application/json": {
                "type": "object",
                "properties": {
                    "latitude": {
                        "type": "number",
                        "description": "Required only for location_time_restricted events"
                    },
                    "longitude": {
                        "type": "number",
                        "description": "Required only for location_time_restricted events"
                    },
                },
            }
        },
        responses={
            201: OpenApiResponse(description="Vote recorded. Returns detail message and updated vote_count."),
            400: OpenApiResponse(description="Already voted, or fewer than 2 songs in queue."),
            403: OpenApiResponse(description="Not allowed to vote on this event."),
        },
        tags=["events"],
    ),
    delete=extend_schema(
        summary="Retract your vote",
        description="Removes your previously cast vote for this song, if you have one.",
        responses={
            200: OpenApiResponse(description="Vote retracted. Returns detail message and updated vote_count."),
            400: OpenApiResponse(description="You have not voted for this song."),
        },
        tags=["events"],
    ),
)
class VoteView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [VoteRateThrottle] 
    def post(self, request, event_id, event_song_id):
        event = get_object_or_404(Event, id=event_id)
        event_song = get_object_or_404(EventSong, id=event_song_id, event=event)

        user_latitude = request.data.get("latitude")
        user_longitude = request.data.get("longitude")

        allowed, reason = can_user_vote(
            request.user, event,
            user_latitude=user_latitude, user_longitude=user_longitude
        )
        if not allowed:
            return Response({"detail": reason}, status=status.HTTP_403_FORBIDDEN)
        try:
            with transaction.atomic():
                Vote.objects.create(event_song=event_song, voter=request.user)
        except IntegrityError:
            return Response({"detail": "You have already voted for this song."},
                             status=status.HTTP_400_BAD_REQUEST)

        log_action(request, "event.vote_cast", user=request.user)
        broadcast_queue_update(event)
        return Response(
            {"detail": "Vote recorded.", "vote_count": event_song.vote_count},
            status=status.HTTP_201_CREATED
        )

    def delete(self, request, event_id, event_song_id):
        """Retract a previously cast vote."""
        event_song = get_object_or_404(EventSong, id=event_song_id, event_id=event_id)
        deleted, _ = Vote.objects.filter(event_song=event_song, voter=request.user).delete()

        if not deleted:
            return Response({"detail": "You have not voted for this song."},
                             status=status.HTTP_400_BAD_REQUEST)

        log_action(request, "event.vote_retracted", user=request.user)
        broadcast_queue_update(event_song.event) 
        return Response(
            {"detail": "Vote retracted.", "vote_count": event_song.vote_count},
            status=status.HTTP_200_OK
        )