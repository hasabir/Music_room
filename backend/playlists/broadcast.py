# playlists/broadcast.py
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def broadcast_playlist_update(playlist):
    from .serializers import (
        PlaylistCollaboratorSerializer,
        PlaylistSerializer,
        PlaylistSongSerializer,
    )

    channel_layer = get_channel_layer()
    room_group_name = f"playlist_{playlist.id}"

    songs = playlist.songs.all()  # ordered by position
    serialized = PlaylistSongSerializer(songs, many=True).data
    collaborators = playlist.collaborators.select_related("collaborator").all()

    async_to_sync(channel_layer.group_send)(
        room_group_name,
        {
            "type": "playlist.update",  # maps to PlaylistConsumer.playlist_update()
            "data": {
                "playlist_id": playlist.id,
                "playlist": PlaylistSerializer(playlist).data,
                "songs": serialized,
                "collaborators": PlaylistCollaboratorSerializer(collaborators, many=True).data,
            },
        }
    )
