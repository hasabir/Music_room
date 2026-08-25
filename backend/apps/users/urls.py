from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    RegisterView,
    LoginView,
    SocialAuthView,
    LinkSocialAccountView,
    VerifyEmailView,
    ResendVerificationEmailView,
    PasswordResetRequestView,
    PasswordResetConfirmView,
    PasswordChangeView,
    UserProfileView,
    MusicPreferencesView,
    UserDetailView,
    SendFriendRequestView,
    RespondToFriendRequestView,
    FriendListView,
    FriendRequestsListView,
)

app_name = 'users'

urlpatterns = [
    # Authentication
    path('auth/register/', RegisterView.as_view(), name='register'),
    path('auth/login/', LoginView.as_view(), name='login'),
    path('auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('auth/social/', SocialAuthView.as_view(), name='social_auth'),
    path('auth/link-social/', LinkSocialAccountView.as_view(), name='link_social'),
    
    # Email verification
    path('auth/verify-email/', VerifyEmailView.as_view(), name='verify_email'),
    path('auth/resend-verification/', ResendVerificationEmailView.as_view(), name='resend_verification'),
    
    # Password management
    path('auth/password/reset/', PasswordResetRequestView.as_view(), name='password_reset_request'),
    path('auth/password/reset/confirm/', PasswordResetConfirmView.as_view(), name='password_reset_confirm'),
    path('auth/password/change/', PasswordChangeView.as_view(), name='password_change'),
    
    # User profile
    path('profile/', UserProfileView.as_view(), name='user_profile'),
    path('profile/music-preferences/', MusicPreferencesView.as_view(), name='music_preferences'),
    path('users/<int:user_id>/', UserDetailView.as_view(), name='user_detail'),
    
    # Friends
    path('friends/', FriendListView.as_view(), name='friend_list'),
    path('friends/requests/', FriendRequestsListView.as_view(), name='friend_requests'),
    path('friends/request/', SendFriendRequestView.as_view(), name='send_friend_request'),
    path('friends/request/<int:friendship_id>/respond/', RespondToFriendRequestView.as_view(), name='respond_friend_request'),
]
