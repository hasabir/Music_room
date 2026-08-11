# playlists/routing.py
from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    re_path(r'ws/playlists/(?P<playlist_id>\d+)/$', consumers.PlaylistConsumer.as_asgi()),
]