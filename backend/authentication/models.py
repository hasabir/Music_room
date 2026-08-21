# authentication/models.py
import random
from django.db import models
from django.conf import settings
from django.utils import timezone
from datetime import timedelta


class OTPCode(models.Model):
    PURPOSE_CHOICES = [
        ("verify_email", "Email Verification"),
        ("password_reset", "Password Reset"),
    ]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="otp_codes")
    code = models.CharField(max_length=6)
    purpose = models.CharField(max_length=20, choices=PURPOSE_CHOICES)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used = models.BooleanField(default=False)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.purpose} code for {self.user.email}"

    @staticmethod
    def generate_code():
        return f"{random.randint(0, 999999):06d}"  # always 6 digits, zero-padded

    @classmethod
    def create_for_user(cls, user, purpose, ttl_minutes=15):
        # Invalidate any previous unused codes of the same purpose,
        # so only the most recently sent code is ever valid
        cls.objects.filter(user=user, purpose=purpose, used=False).update(used=True)

        return cls.objects.create(
            user=user,
            code=cls.generate_code(),
            purpose=purpose,
            expires_at=timezone.now() + timedelta(minutes=ttl_minutes),
        )

    def is_valid(self):
        return not self.used and timezone.now() < self.expires_at