from django.db import models
from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.utils.translation import gettext_lazy as _
import uuid


class CustomUserManager(BaseUserManager):
    """Custom user manager for email-based authentication"""
    
    def create_user(self, email, password=None, **extra_fields):
        """Create and return a regular user with an email and password"""
        if not email:
            raise ValueError(_('The Email field must be set'))
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user
    
    def create_superuser(self, email, password=None, **extra_fields):
        """Create and return a superuser with an email and password"""
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)
        extra_fields.setdefault('email_verified', True)
        
        if extra_fields.get('is_staff') is not True:
            raise ValueError(_('Superuser must have is_staff=True.'))
        if extra_fields.get('is_superuser') is not True:
            raise ValueError(_('Superuser must have is_superuser=True.'))
        
        return self.create_user(email, password, **extra_fields)


class User(AbstractUser):
    """Custom User model for Music Room application"""
    
    # Remove username, use email as primary identifier
    username = None
    email = models.EmailField(_('email address'), unique=True)
    
    # Email verification
    email_verified = models.BooleanField(default=False)
    email_verification_token = models.UUIDField(default=uuid.uuid4, editable=False)
    
    # Social authentication
    facebook_id = models.CharField(max_length=255, blank=True, null=True, unique=True)
    google_id = models.CharField(max_length=255, blank=True, null=True, unique=True)
    
    # Public information - visible to everyone
    display_name = models.CharField(max_length=100, blank=True)
    avatar = models.ImageField(upload_to='avatars/', blank=True, null=True)
    bio = models.TextField(blank=True)
    
    # Friends-only information
    phone_number = models.CharField(max_length=20, blank=True)
    location = models.CharField(max_length=100, blank=True)
    
    # Private information (only visible to the user themselves)
    date_of_birth = models.DateField(null=True, blank=True)
    
    # Music preferences
    favorite_genres = models.JSONField(default=list, blank=True)
    favorite_artists = models.JSONField(default=list, blank=True)
    music_services = models.JSONField(default=dict, blank=True)  # Spotify, Apple Music, etc.
    
    # Subscription management
    SUBSCRIPTION_CHOICES = [
        ('free', 'Free'),
        ('premium', 'Premium'),
        ('pro', 'Professional'),
    ]
    subscription_type = models.CharField(
        max_length=10,
        choices=SUBSCRIPTION_CHOICES,
        default='free'
    )
    subscription_expires_at = models.DateTimeField(null=True, blank=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    objects = CustomUserManager()
    
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []
    
    class Meta:
        verbose_name = _('user')
        verbose_name_plural = _('users')
        ordering = ['-created_at']
    
    def __str__(self):
        return self.email
    
    def get_public_info(self):
        """Return public information visible to all users"""
        return {
            'id': self.id,
            'email': self.email,
            'display_name': self.display_name,
            'avatar': self.avatar.url if self.avatar else None,
            'bio': self.bio,
        }
    
    def get_friends_info(self):
        """Return information visible to friends"""
        info = self.get_public_info()
        info.update({
            'phone_number': self.phone_number,
            'location': self.location,
        })
        return info
    
    def get_full_info(self):
        """Return all information (private, for the user themselves)"""
        info = self.get_friends_info()
        info.update({
            'date_of_birth': self.date_of_birth,
            'favorite_genres': self.favorite_genres,
            'favorite_artists': self.favorite_artists,
            'music_services': self.music_services,
            'subscription_type': self.subscription_type,
        })
        return info


class Friendship(models.Model):
    """Model to manage friendships between users"""
    
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('rejected', 'Rejected'),
        ('blocked', 'Blocked'),
    ]
    
    from_user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='sent_friend_requests'
    )
    to_user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='received_friend_requests'
    )
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        unique_together = ('from_user', 'to_user')
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.from_user.email} -> {self.to_user.email} ({self.status})"


class PasswordResetToken(models.Model):
    """Model to manage password reset tokens"""
    
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    token = models.UUIDField(default=uuid.uuid4, editable=False, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    used = models.BooleanField(default=False)
    
    class Meta:
        ordering = ['-created_at']
    
    def __str__(self):
        return f"Reset token for {self.user.email}"
    
    def is_valid(self):
        """Check if the token is still valid (not older than 24 hours)"""
        from django.utils import timezone
        from datetime import timedelta
        return not self.used and (timezone.now() - self.created_at) < timedelta(hours=24)
