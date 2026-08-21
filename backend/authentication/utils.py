# user/utils.py
from django.core.mail import send_mail
from django.utils.http import urlsafe_base64_encode
from django.utils.encoding import force_bytes
from django.conf import settings
from django.contrib.auth.tokens import default_token_generator
from .tokens import email_verification_token
from django.conf import settings
from user.models import ActionLog
from .models import OTPCode


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


def send_verification_email(user):
    otp = OTPCode.create_for_user(user, purpose="verify_email", ttl_minutes=15)

    if not settings.EMAIL_DEV_MODE:
        send_mail(
            subject="Verify your Music Room account",
            message=(
                f"Hi {user.first_name},\n\n"
                f"Your verification code is: {otp.code}\n\n"
                f"This code expires in 15 minutes.\n\n"
                f"If you didn't create this account, ignore this email."
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
        )

    return {"code": otp.code, "expires_at": otp.expires_at.isoformat()}


def send_password_reset_email(user):
    otp = OTPCode.create_for_user(user, purpose="password_reset", ttl_minutes=15)

    if not settings.EMAIL_DEV_MODE:
        send_mail(
            subject="Reset your Music Room password",
            message=(
                f"Hi {user.first_name},\n\n"
                f"Your password reset code is: {otp.code}\n\n"
                f"This code expires in 15 minutes.\n\n"
                f"If you didn't request this, ignore this email."
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
        )

    return {"code": otp.code, "expires_at": otp.expires_at.isoformat()}