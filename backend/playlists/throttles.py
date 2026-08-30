# playlists/throttles.py
from rest_framework.throttling import UserRateThrottle


class AddPlaylistSongRateThrottle(UserRateThrottle):
    scope = "add_playlist_song"


class MoveSongRateThrottle(UserRateThrottle):
    scope = "move_song"


class CreatePlaylistRateThrottle(UserRateThrottle):
    scope = "create_playlist"


class AccessRequestRateThrottle(UserRateThrottle):
    scope = "playlist_access_request"