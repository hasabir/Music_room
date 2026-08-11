# events/consumers.py
import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async


class EventQueueConsumer(AsyncWebsocketConsumer):
    """
    One WebSocket connection = one phone watching one event's live queue.

    Room naming: every event has its own "room" (a Channels group).
    Everyone connected to the same event's room receives the same broadcasts.
    """

    async def connect(self):
        self.event_id = self.scope["url_route"]["kwargs"]["event_id"]
        self.room_group_name = f"event_queue_{self.event_id}"

        # Only allow authenticated users to connect
        user = self.scope.get("user")
        if user is None or not user.is_authenticated:
            await self.close(code=4001)  # custom code: unauthenticated
            return

        # Check the user is actually allowed to see this event
        allowed = await self._can_user_see_event(user, self.event_id)
        if not allowed:
            await self.close(code=4003)  # custom code: forbidden
            return

        # Join the room
        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        # Leave the room when the phone disconnects
        if hasattr(self, "room_group_name"):
            await self.channel_layer.group_discard(self.room_group_name, self.channel_name)

    async def receive(self, text_data):
        # We don't expect the client to send anything meaningful right now —
        # this connection is one-directional (server -> client) for the vote feature.
        # Left here in case you want ping/pong or client-initiated actions later.
        pass

    # ---- Handlers for messages broadcast into this room ----

    async def queue_update(self, event):
        """
        Called automatically by Channels when something sends a message
        of type "queue.update" into this room (see utils.py below).
        Forwards that message straight to the connected phone as JSON.
        """
        await self.send(text_data=json.dumps(event["data"]))

    # ---- Helpers ----

    @database_sync_to_async
    def _can_user_see_event(self, user, event_id):
        from .models import Event
        from .permissions import can_user_see_event
        try:
            event = Event.objects.get(id=event_id)
        except Event.DoesNotExist:
            return False
        return can_user_see_event(user, event)