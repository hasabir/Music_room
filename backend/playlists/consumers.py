# playlists/consumers.py
import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async


class PlaylistConsumer(AsyncWebsocketConsumer):
    """One WebSocket connection = one phone watching one playlist live."""

    async def connect(self):
        self.playlist_id = self.scope["url_route"]["kwargs"]["playlist_id"]
        self.room_group_name = f"playlist_{self.playlist_id}"

        user = self.scope.get("user")
        if user is None or not user.is_authenticated:
            await self.close(code=4001)
            return

        allowed = await self._can_user_see_playlist(user, self.playlist_id)
        if not allowed:
            await self.close(code=4003)
            return

        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        if hasattr(self, "room_group_name"):
            await self.channel_layer.group_discard(self.room_group_name, self.channel_name)

    async def receive(self, text_data):
        pass  # one-directional (server -> client) for now

    async def playlist_update(self, event):
        await self.send(text_data=json.dumps(event["data"]))

    @database_sync_to_async
    def _can_user_see_playlist(self, user, playlist_id):
        from .models import Playlist
        from .permissions import can_user_see_playlist
        try:
            playlist = Playlist.objects.get(id=playlist_id)
        except Playlist.DoesNotExist:
            return False
        return can_user_see_playlist(user, playlist)