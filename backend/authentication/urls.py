# authentication/urls.py
from django.urls import path
from .views import (
    RegisterView,
    LoginView ,VerifyEmailView,
    ResendVerificationEmailView, PasswordResetRequestView,
    PasswordResetVerifyCodeView, PasswordResetSetNewPasswordView,
    GoogleLoginView, GoogleLinkView,
    LogoutView
)
from rest_framework_simplejwt.views import TokenRefreshView

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('login/', LoginView.as_view(), name='login'),
    path("google/", GoogleLoginView.as_view(), name="google-login"),
    path("google/link/", GoogleLinkView.as_view(), name="google-link"),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('verify-email/', VerifyEmailView.as_view(), name='verify_email'),
    path('resend-verification/', ResendVerificationEmailView.as_view(), name='resend_verification'),
    path('password-reset/', PasswordResetRequestView.as_view(), name='password_reset_request'),
    path('password-reset/verify-code/', PasswordResetVerifyCodeView.as_view(), name='password_reset_verify_code'),
    path('password-reset/set-new-password/', PasswordResetSetNewPasswordView.as_view(), name='password_reset_set_new_password'),]