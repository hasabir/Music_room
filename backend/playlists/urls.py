# playlists/urls.py
from django.urls import path
from .views import (
    PlaylistListCreateView, PlaylistDetailView,
    PlaylistSongListView, PlaylistSongDeleteView, PlaylistSongMoveView
)
from .views_collaborators import PlaylistCollaboratorListView, PlaylistCollaboratorRemoveView
from .views_access_requests import (
    PlaylistAccessRequestListCreateView, PlaylistAccessRequestMineView, PlaylistAccessRequestDecideView
)

urlpatterns = [
    path('', PlaylistListCreateView.as_view(), name='playlist_list_create'),
    path('<int:pk>/', PlaylistDetailView.as_view(), name='playlist_detail'),
    path('<int:playlist_id>/songs/', PlaylistSongListView.as_view(), name='playlist_songs'),
    path('<int:playlist_id>/songs/<int:playlist_song_id>/', PlaylistSongDeleteView.as_view(), name='playlist_song_delete'),
    path('<int:playlist_id>/songs/<int:playlist_song_id>/move/', PlaylistSongMoveView.as_view(), name='playlist_song_move'),
    path('<int:playlist_id>/collaborators/', PlaylistCollaboratorListView.as_view(), name='playlist_collaborator_list'),
    path('<int:playlist_id>/collaborators/<int:user_id>/', PlaylistCollaboratorRemoveView.as_view(), name='playlist_collaborator_remove'),
    path('<int:playlist_id>/access-requests/', PlaylistAccessRequestListCreateView.as_view(), name='playlist_access_request_list_create'),
    path('<int:playlist_id>/access-requests/mine/', PlaylistAccessRequestMineView.as_view(), name='playlist_access_request_mine'),
    path('<int:playlist_id>/access-requests/<int:request_id>/decide/', PlaylistAccessRequestDecideView.as_view(), name='playlist_access_request_decide'),
]