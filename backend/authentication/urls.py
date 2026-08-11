# authentication/urls.py
from django.urls import path
from .views import (
    RegisterView, 
    LoginView ,VerifyEmailView, 
    ResendVerificationEmailView, PasswordResetRequestView, 
    PasswordResetConfirmView,GoogleLoginView
)
from rest_framework_simplejwt.views import TokenRefreshView

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', LoginView.as_view(), name='login'),
    path("google/", GoogleLoginView.as_view(), name="google-login"),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('verify-email/', VerifyEmailView.as_view(), name='verify_email'),
    path('resend-verification/', ResendVerificationEmailView.as_view(), name='resend_verification'),
    path('password-reset/', PasswordResetRequestView.as_view(), name='password_reset_request'),
    path('password-reset/confirm/', PasswordResetConfirmView.as_view(), name='password_reset_confirm'),
]