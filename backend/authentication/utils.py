# user/utils.py
from django.core.mail import send_mail
from django.utils.http import urlsafe_base64_encode
from django.utils.encoding import force_bytes
from django.conf import settings
from django.contrib.auth.tokens import default_token_generator
from .tokens import email_verification_token
from django.conf import settings
from user.models import ActionLog


def log_action(request, action, user=None):
    ActionLog.objects.create(
        user=user,
        action=action,
        platform=request.headers.get("X-Platform", ""),
        device=request.headers.get("X-Device", ""),
        app_version=request.headers.get("X-App-Version", ""),
        ip_address=get_client_ip(request),
    )


def get_client_ip(request):
    forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")

    if forwarded_for:
        return forwarded_for.split(",")[0].strip()

    return request.META.get("REMOTE_ADDR")
    

def build_verification_link(user, frontend_base_url):
    uid = urlsafe_base64_encode(force_bytes(user.pk))
    token = email_verification_token.make_token(user)
    return f"{frontend_base_url}/verify-email?uid={uid}&token={token}", uid, token


def build_password_reset_link(user, frontend_base_url):
    uid = urlsafe_base64_encode(force_bytes(user.pk))
    token = default_token_generator.make_token(user)
    return f"{frontend_base_url}/reset-password?uid={uid}&token={token}", uid, token


def send_verification_email(user, frontend_base_url):
    link, uid, token = build_verification_link(user, frontend_base_url)

    if not settings.EMAIL_DEV_MODE:
        send_mail(
            subject="Verify your Music Room account",
            message=f"Hi {user.first_name},\n\nPlease verify your email by using this link:\n{link}\n\nIf you didn't create this account, ignore this email.",
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
        )

    return {"link": link, "uid": uid, "token": token}


def send_password_reset_email(user, frontend_base_url):
    link, uid, token = build_password_reset_link(user, frontend_base_url)

    if not settings.EMAIL_DEV_MODE:
        send_mail(
            subject="Reset your Music Room password",
            message=f"Hi {user.first_name},\n\nReset your password using this link:\n{link}\n\nIf you didn't request this, ignore this email.",
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
        )

    return {"link": link, "uid": uid, "token": token}