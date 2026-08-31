# events/broadcast.py
"""
Call broadcast_queue_update(event) after any change to an event's queue
(vote cast, vote retracted, song added) to push the fresh queue to every
phone currently connected to that event's WebSocket room.
"""
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def broadcast_queue_update(event):
    from .serializers import EventSongSerializer, EventGuestSerializer

    channel_layer = get_channel_layer()
    room_group_name = f"event_queue_{event.id}"

    # Most-voted first; a tie goes to whichever song reached that vote
    # count first — see EventSong.rank_sort_key.
    queue = sorted(event.queue.exclude(status="played"), key=lambda es: es.rank_sort_key())
    # NOTE: has_voted is per-user and can't be computed here (no request/user
    # in this context) — it's set to False for all entries in the broadcast.
    # The client should rely on its own local vote state for that flag, or
    # the REST GET /queue/ endpoint for the fully accurate per-user view.
    serialized = EventSongSerializer(queue, many=True).data
    guests = EventGuestSerializer(event.guests.select_related("guest").all(), many=True).data

    async_to_sync(channel_layer.group_send)(
        room_group_name,
        {
            "type": "queue.update",  # maps to EventQueueConsumer.queue_update()
            "data": {
                "event_id": event.id,
                "queue": serialized,
                "guests": guests,
            },
        }
    )