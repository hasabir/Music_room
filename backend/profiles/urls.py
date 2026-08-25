from django.urls import path

from .views import (
    SendFriendRequestView,
    AcceptFriendRequestView,
    RejectFriendRequestView,
    RemoveFriendView,
    FriendListView,
    PendingFriendRequestListView,
    MyProfileView,
    UserProfileView,
    MyActivityView,
    UserActivityView,

)


urlpatterns = [

    path(
        "friends/",
        FriendListView.as_view(),
        name="friend-list"
    ),

    path(
        "friends/requests/",
        PendingFriendRequestListView.as_view(),
        name="pending-friend-requests"
    ),

    path(
        "friends/<int:user_id>/add/",
        SendFriendRequestView.as_view(),
        name="send-friend-request"
    ),

    path(
        "friends/requests/<int:request_id>/accept/",
        AcceptFriendRequestView.as_view(),
        name="accept-friend-request"
    ),

    path(
        "friends/requests/<int:request_id>/reject/",
        RejectFriendRequestView.as_view(),
        name="reject-friend-request"
    ),

    path(
        "friends/<int:user_id>/remove/",
        RemoveFriendView.as_view(),
        name="remove-friend"
    ),
    path("me/", MyProfileView.as_view(), name="my-profile"),
    path("me/activity/", MyActivityView.as_view(), name="my-activity"),
    # friends/urls.py
    path('profile/<int:user_id>/', UserProfileView.as_view(), name='user_profile'),
    path('profile/<int:user_id>/activity/', UserActivityView.as_view(), name='user-activity'),
]