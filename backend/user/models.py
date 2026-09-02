import re

from django.db import models
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.core.validators import RegexValidator


class UserManager(BaseUserManager):
    def _generated_username(self, email):
        base = re.sub(r"[^a-z0-9_.]", "", email.split("@", 1)[0].lower())
        base = (base or "musicroom")[:24]
        if len(base) < 3:
            base = f"{base}user"[:24]
        candidate = base
        suffix = 1
        while self.model.objects.filter(username__iexact=candidate).exists():
            suffix_text = str(suffix)
            candidate = f"{base[:30 - len(suffix_text)]}{suffix_text}"
            suffix += 1
        return candidate

    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError("Users must have an email address")
        email = self.normalize_email(email)
        if not extra_fields.get("username"):
            extra_fields["username"] = self._generated_username(email)
        user = self.model(email=email, **extra_fields)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()  # for Google-only signups
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        return self.create_user(email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    REGISTRATION_CHOICES = [
        ('email', 'Email'),
        ('google', 'Google'),
    ]

    email = models.EmailField(unique=True)
    username = models.CharField(
        max_length=30,
        unique=True,
        validators=[
            RegexValidator(
                r"^[A-Za-z0-9_.]{3,30}$",
                "Username must be 3–30 letters, numbers, dots, or underscores.",
            ),
        ],
    )
    first_name = models.CharField(max_length=30, blank=True)
    last_name = models.CharField(max_length=30, blank=True)
    registration_method = models.CharField(
        max_length=10, choices=REGISTRATION_CHOICES, default='email'
    )
    is_email_verified = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    date_joined = models.DateTimeField(auto_now_add=True)

    objects = UserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []  # email + password already required by USERNAME_FIELD/AbstractBaseUser

    def __str__(self):
        return self.username

class SocialAccount(models.Model):
    # unique=True: at most one linked Google account per user (reject, not
    # replace, a second link attempt — see DECISIONS.md).
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='social_accounts', unique=True)
    provider_uid = models.CharField(max_length=255, unique=True)  # Google's unique 'sub' claim
    # The Google account's own email, independent of User.email — linking
    # never requires (or touches) the platform email. See DECISIONS.md.
    email = models.EmailField()
    linked_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Google account for {self.user.email}"
class ActionLog(models.Model):
    user = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='action_logs')
    action = models.CharField(max_length=100)
    platform = models.CharField(max_length=20, blank=True)
    device = models.CharField(max_length=100, blank=True)
    app_version = models.CharField(max_length=20, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    # Free-form per-action context (e.g. playlist/room title + visibility)
    # used to render human-readable activity feed entries without a join.
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.action} by {self.user or 'anonymous'} at {self.created_at}"
