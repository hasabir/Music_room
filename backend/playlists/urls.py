# playlists/urls.py
from django.urls import path
from .views import (
    PlaylistListCreateView, PlaylistDetailView,
    PlaylistSongListView, PlaylistSongDeleteView, PlaylistSongMoveView
)

urlpatterns = [
    path('', PlaylistListCreateView.as_view(), name='playlist_list_create'),
    path('<int:pk>/', PlaylistDetailView.as_view(), name='playlist_detail'),
    path('<int:playlist_id>/songs/', PlaylistSongListView.as_view(), name='playlist_songs'),
    path('<int:playlist_id>/songs/<int:playlist_song_id>/', PlaylistSongDeleteView.as_view(), name='playlist_song_delete'),
    path('<int:playlist_id>/songs/<int:playlist_song_id>/move/', PlaylistSongMoveView.as_view(), name='playlist_song_move'),
]