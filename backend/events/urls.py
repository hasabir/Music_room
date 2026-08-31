# events/urls.py
from django.urls import path
from .views import EventListCreateView, EventDetailView, EventQueueView, VoteView
from .views_guests import (
    EventGuestListView, EventGuestRemoveView, EventGuestRespondView, EventJoinView,
    EventAttendeeListView, EventAttendeeRemoveView,
)
from .views_access_requests import (
    EventAccessRequestListCreateView, EventAccessRequestMineView, EventAccessRequestDecideView
)

urlpatterns = [
    path('', EventListCreateView.as_view(), name='event_list_create'),
    path('<int:pk>/', EventDetailView.as_view(), name='event_detail'),
    path('<int:event_id>/queue/', EventQueueView.as_view(), name='event_queue'),
    path('<int:event_id>/queue/<int:event_song_id>/vote/', VoteView.as_view(), name='event_song_vote'),
    path('<int:event_id>/guests/', EventGuestListView.as_view(), name='event_guest_list'),
    path('<int:event_id>/guests/respond/', EventGuestRespondView.as_view(), name='event_guest_respond'),
    path('<int:event_id>/guests/<int:user_id>/', EventGuestRemoveView.as_view(), name='event_guest_remove'),
    path('<int:event_id>/join/', EventJoinView.as_view(), name='event_join'),
    path('<int:event_id>/attendees/', EventAttendeeListView.as_view(), name='event_attendee_list'),
    path('<int:event_id>/attendees/<int:user_id>/', EventAttendeeRemoveView.as_view(), name='event_attendee_remove'),
    path('<int:event_id>/access-requests/', EventAccessRequestListCreateView.as_view(), name='event_access_request_list_create'),
    path('<int:event_id>/access-requests/mine/', EventAccessRequestMineView.as_view(), name='event_access_request_mine'),
    path('<int:event_id>/access-requests/<int:request_id>/decide/', EventAccessRequestDecideView.as_view(), name='event_access_request_decide'),
]