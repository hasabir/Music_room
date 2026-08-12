# playlists/urls.py
from django.urls import path
from .views import (
    PlaylistListCreateView, PlaylistDetailView,
    PlaylistSongListView, PlaylistSongDeleteView, PlaylistSongMoveView
)
from .views_collaborators import PlaylistCollaboratorListView, PlaylistCollaboratorRemoveView

urlpatterns = [
    path('', PlaylistListCreateView.as_view(), name='playlist_list_create'),
    path('<int:pk>/', PlaylistDetailView.as_view(), name='playlist_detail'),
    path('<int:playlist_id>/songs/', PlaylistSongListView.as_view(), name='playlist_songs'),
    path('<int:playlist_id>/songs/<int:playlist_song_id>/', PlaylistSongDeleteView.as_view(), name='playlist_song_delete'),
    path('<int:playlist_id>/songs/<int:playlist_song_id>/move/', PlaylistSongMoveView.as_view(), name='playlist_song_move'),
    path('<int:playlist_id>/collaborators/', PlaylistCollaboratorListView.as_view(), name='playlist_collaborator_list'),
    path('<int:playlist_id>/collaborators/<int:user_id>/', PlaylistCollaboratorRemoveView.as_view(), name='playlist_collaborator_remove'),
]