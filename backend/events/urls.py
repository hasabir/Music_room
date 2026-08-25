# events/urls.py
from django.urls import path
from .views import EventListCreateView, EventDetailView, EventQueueView, VoteView
from .views_guests import EventGuestListView, EventGuestRemoveView, EventJoinView

urlpatterns = [
    path('', EventListCreateView.as_view(), name='event_list_create'),
    path('<int:pk>/', EventDetailView.as_view(), name='event_detail'),
    path('<int:event_id>/queue/', EventQueueView.as_view(), name='event_queue'),
    path('<int:event_id>/queue/<int:event_song_id>/vote/', VoteView.as_view(), name='event_song_vote'),
    path('<int:event_id>/guests/', EventGuestListView.as_view(), name='event_guest_list'),
    path('<int:event_id>/guests/<int:user_id>/', EventGuestRemoveView.as_view(), name='event_guest_remove'),
    path('<int:event_id>/join/', EventJoinView.as_view(), name='event_join'),
]