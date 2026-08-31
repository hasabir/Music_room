# events/views.py
from django.db import IntegrityError , transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
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
            "becomes the host. `vote_permission` (`everyone`/`invited_only`) "
            "controls who can vote at all; `time_restriction_enabled` and "
            "`location_restriction_enabled` are independent toggles that "
            "layer on top of either — enable one, both, or neither. "
            "Enabling `time_restriction_enabled` requires `voting_opens_at`/"
            "`voting_closes_at`; enabling `location_restriction_enabled` "
            "requires venue coordinates and `allowed_distance_meters`."
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
        # A deleted event is excluded here for everyone, host included —
        # it only remains reachable by direct GET .../<id>/ for a past
        # guest/member (see can_user_see_event), which is what lets the
        # event page still show "this event has been deleted".
        return Event.objects.filter(
            Q(visibility="public") | Q(host=user) | Q(guests__guest=user)
        ).exclude(status=Event.STATUS_DELETED).distinct()

    def perform_create(self, serializer):
        event = serializer.save(host=self.request.user)
        log_action(self.request, "event.created", user=self.request.user, metadata={
            "event_id": event.id,
            "title": event.title,
            "visibility": event.visibility,
        })


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
        # Catches the event's authoritative playback state up to now before
        # it's serialized — this is what a new joiner or a rejoining user
        # syncs to (see `Event.sync_current_song`).
        event.sync_current_song()
        event.sync_activity_status()
        return event

    def perform_update(self, serializer):
        if serializer.instance.host_id != self.request.user.id:
            raise PermissionDenied("Only the host can edit this event.")
        serializer.save()

    def perform_destroy(self, instance):
        """
        Soft delete: the row (and its queue/votes/guests/members) is kept,
        not removed — see Event.STATUS_DELETED's doc comment. This is what
        lets a guest/member who already has the event page open learn
        "this event has been deleted" (via the existing poll picking up
        the status change) instead of just hitting a 404, and is also why
        this stays a 204 response like a real delete — the client-visible
        contract doesn't change.
        """
        if instance.host_id != self.request.user.id:
            raise PermissionDenied("Only the host can delete this event.")
        instance.status = Event.STATUS_DELETED
        instance.deleted_at = timezone.now()
        instance.save(update_fields=["status", "deleted_at"])
        log_action(self.request, "event.deleted", user=self.request.user, metadata={
            "event_id": instance.id,
            "title": instance.title,
            "visibility": instance.visibility,
        })


@extend_schema_view(
    get=extend_schema(
        summary="List the song queue",
        description=(
            "Returns the not-yet-played songs in this event's queue, "
            "sorted by vote count (most-voted first). This is the "
            "ranked list that determines what plays next; a song is "
            "left out once its playback time has genuinely elapsed (see "
            "`Event.sync_current_song`), not by any client request."
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
            "song is already in this event's queue (`queued` or "
            "`playing`) — but a song that's already been played can be "
            "added again, starting fresh with no votes."
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

        event.sync_current_song()
        event.sync_activity_status()
        # Most-voted first; a tie goes to whichever song reached that
        # vote count first — see EventSong.rank_sort_key.
        queue = sorted(
            event.queue.exclude(status="played"),
            key=lambda es: es.rank_sort_key()
        )
        serializer = EventSongSerializer(queue, many=True, context={"request": request})
        return Response(serializer.data)

    def post(self, request, event_id):
        event = get_object_or_404(Event, id=event_id)
        if not can_user_see_event(request.user, event):
            return Response({"detail": "You do not have access to this event."},
                             status=status.HTTP_403_FORBIDDEN)

        # Closed: viewing/voting stays open, but the queue is frozen — no
        # new track suggestions from anyone, host included. Canceled is a
        # stricter superset of that (and already blocks everyone but the
        # host from reaching this point at all, via can_user_see_event
        # above) — the host still can't add to a canceled event's queue.
        if event.status == Event.STATUS_CLOSED:
            return Response({"detail": "This event is closed — new tracks can no longer be suggested."},
                             status=status.HTTP_403_FORBIDDEN)
        if event.status == Event.STATUS_CANCELED:
            return Response({"detail": "This event has been canceled."},
                             status=status.HTTP_403_FORBIDDEN)
        if event.status == Event.STATUS_DELETED:
            return Response({"detail": "This event has been deleted."},
                             status=status.HTTP_403_FORBIDDEN)

        serializer = AddSongToQueueSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        song_defaults = {
            "title": data["title"],
            "artist": data["artist"],
            "duration_seconds": data.get("duration_seconds"),
            "external_id": data.get("external_id", ""),
            "album_art_url": data.get("album_art_url", ""),
            "preview_url": data.get("preview_url", ""),
            "playback_type": data.get("playback_type", "preview"),
        }
        external_id = data.get("external_id", "")
        if external_id:
            # A title/artist can exist at multiple providers. Keep the
            # provider-specific entry so an Audius full stream never gets
            # replaced by a same-named Deezer preview — mirrors playlists'
            # add-song matching (playlists/views.py) so the same track
            # doesn't fork into two different Song rows depending on
            # whether it's added to an event or a playlist first.
            song, _ = Song.objects.get_or_create(
                external_id=external_id,
                defaults=song_defaults,
            )
        else:
            song, _ = Song.objects.get_or_create(
                title__iexact=data["title"],
                artist__iexact=data["artist"],
                defaults=song_defaults,
            )

        # Catch the event up to now first — otherwise a song whose real
        # playtime already elapsed could still read as stale `playing`
        # data from before this request, and get wrongly rejected below as
        # "already in the queue" instead of being recognized as revivable.
        event.sync_current_song()

        event_song, created = EventSong.objects.get_or_create(
            event=event, song=song, defaults={"added_by": request.user}
        )
        revived = False
        if not created:
            if event_song.status != "played":
                return Response({"detail": "This song is already in the queue."},
                                 status=status.HTTP_400_BAD_REQUEST)
            # It already had its turn and dropped out of the queue (see
            # `Event.sync_current_song`) — `unique_together` means it can't
            # become a second row, so bring this same one back instead:
            # fresh votes, fresh position, credited to whoever just
            # re-suggested it, same as any other newly-added song.
            revived = True
            event_song.votes.all().delete()
            event_song.status = "queued"
            event_song.added_by = request.user
            event_song.added_at = timezone.now()
            event_song.save(update_fields=["status", "added_by", "added_at"])

        log_action(request, "event.song_added", user=request.user, metadata={
            "event_id": event.id,
            "event_title": event.title,
            "visibility": event.visibility,
            "song_title": song.title,
            "artist": song.artist,
            "revived": revived,
        })
        event.sync_current_song()
        # A fresh suggestion is exactly what resets the inactivity ladder
        # — this naturally drops the event straight back to STATUS_LIVE
        # if it had drifted into ghost_town/rip_attendance/party_of_nobody
        # (see Event.sync_activity_status / Event._last_track_suggested_at).
        event.sync_activity_status()
        # `sync_current_song` may have mutated this exact row's `status`
        # through a separately-fetched instance (e.g. it's the only song,
        # so it just became current) — reload so the response reflects it.
        event_song.refresh_from_db()
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
            "event's `vote_permission` setting plus its two independent "
            "restriction toggles:\n\n"
            "- `vote_permission=everyone`: any user who can see the event "
            "can vote (subject to the restrictions below).\n"
            "- `vote_permission=invited_only`: only the host and invited "
            "guests can vote (subject to the restrictions below).\n"
            "- `time_restriction_enabled`: the current time must be within "
            "the event's `voting_opens_at`/`voting_closes_at` window.\n"
            "- `location_restriction_enabled`: requires `latitude`/"
            "`longitude` in the request body, within `allowed_distance_meters` "
            "of the venue.\n\n"
            "Both restrictions can be enabled together, independent of "
            "which `vote_permission` is set."
        ),
        request={
            "application/json": {
                "type": "object",
                "properties": {
                    "latitude": {
                        "type": "number",
                        "description": "Required only when location_restriction_enabled is true"
                    },
                    "longitude": {
                        "type": "number",
                        "description": "Required only when location_restriction_enabled is true"
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

        log_action(request, "event.vote_cast", user=request.user, metadata={
            "event_id": event.id,
            "event_title": event.title,
            "visibility": event.visibility,
            "song_title": event_song.song.title,
            "artist": event_song.song.artist,
        })
        event.sync_current_song()
        broadcast_queue_update(event)
        return Response(
            {"detail": "Vote recorded.", "vote_count": event_song.vote_count},
            status=status.HTTP_201_CREATED
        )

    def delete(self, request, event_id, event_song_id):
        """Retract a previously cast vote."""
        event_song = get_object_or_404(EventSong, id=event_song_id, event_id=event_id)

        # Retracting isn't "casting a new vote" — the full can_user_vote
        # gate (2-song minimum, location/time window) doesn't apply. But
        # access can be revoked after a vote was cast (e.g. removed as a
        # guest on an invited_only event), so visibility is still required:
        # you shouldn't be able to touch an event you can no longer see.
        if not can_user_see_event(request.user, event_song.event):
            return Response({"detail": "You do not have access to this event."},
                             status=status.HTTP_403_FORBIDDEN)

        deleted, _ = Vote.objects.filter(event_song=event_song, voter=request.user).delete()

        if not deleted:
            return Response({"detail": "You have not voted for this song."},
                             status=status.HTTP_400_BAD_REQUEST)

        log_action(request, "event.vote_retracted", user=request.user, metadata={
            "event_id": event_song.event.id,
            "event_title": event_song.event.title,
            "visibility": event_song.event.visibility,
            "song_title": event_song.song.title,
            "artist": event_song.song.artist,
        })
        event_song.event.sync_current_song()
        broadcast_queue_update(event_song.event)
        return Response(
            {"detail": "Vote retracted.", "vote_count": event_song.vote_count},
            status=status.HTTP_200_OK
        )