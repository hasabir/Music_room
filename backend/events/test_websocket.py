from asgiref.sync import async_to_sync, sync_to_async
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase, override_settings
from rest_framework_simplejwt.tokens import AccessToken

from config.asgi import application
from events.broadcast import broadcast_queue_update
from events.models import Event, EventSong, Song
from user.models import User


IN_MEMORY_CHANNELS = {
    "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"},
}


@override_settings(CHANNEL_LAYERS=IN_MEMORY_CHANNELS)
class EventQueueWebSocketTests(TransactionTestCase):
    def setUp(self):
        self.host = User.objects.create_user(email="ws-host@example.com", password="x")
        self.stranger = User.objects.create_user(email="ws-stranger@example.com", password="x")
        self.event = Event.objects.create(host=self.host, title="WebSocket event", visibility="private")
        song = Song.objects.create(title="WebSocket song", artist="Test artist")
        EventSong.objects.create(event=self.event, song=song, added_by=self.host)

    def token(self, user):
        return str(AccessToken.for_user(user))

    def test_connection_requires_authentication(self):
        async_to_sync(self._assert_rejected)("", 4001)

    def test_private_event_rejects_stranger(self):
        async_to_sync(self._assert_rejected)(f"?token={self.token(self.stranger)}", 4003)

    def test_authorized_subscriber_receives_queue_broadcast(self):
        async_to_sync(self._assert_broadcast_delivered)()

    async def _assert_rejected(self, query, expected_code):
        communicator = WebsocketCommunicator(
            application, f"/ws/events/{self.event.id}/queue/{query}"
        )
        connected, close_code = await communicator.connect()
        self.assertFalse(connected)
        self.assertEqual(close_code, expected_code)

    async def _assert_broadcast_delivered(self):
        communicator = WebsocketCommunicator(
            application,
            f"/ws/events/{self.event.id}/queue/?token={self.token(self.host)}",
        )
        connected, _ = await communicator.connect()
        self.assertTrue(connected)
        await sync_to_async(broadcast_queue_update, thread_sensitive=True)(self.event)
        payload = await communicator.receive_json_from(timeout=2)
        self.assertEqual(payload["event_id"], self.event.id)
        self.assertEqual(len(payload["queue"]), 1)
        await communicator.disconnect()
