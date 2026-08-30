import random

from django.conf import settings
from django.db import models
from user.models import User
from django.contrib.postgres.fields import ArrayField

class Friendship(models.Model):

    STATUS_CHOICES = [
        ("pending", "Pending"),
        ("accepted", "Accepted"),
        ("rejected", "Rejected"),
    ]

    sender = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="sent_friend_requests"
    )

    receiver = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="received_friend_requests"
    )

    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default="pending"
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["sender", "receiver"],
                name="unique_friend_request"
            )
        ]

    def __str__(self):
        return (
            f"{self.sender.email} -> "
            f"{self.receiver.email} ({self.status})"
        )




def _default_field_visibility():
    return {
        "bio": "public",
        "location": "friends",
        "favorite_artist": "friends",
        "phone_number": "private",
        "birthday": "friends",
        "activity": "public",
    }


# The preset avatar grid, mirroring the shipped image files under
# mobile/assets/images/avatars/. An id here is just a stable key — the
# mobile app owns the id -> asset-file mapping (see `AvatarPreset` in
# lib/profile/profile_models.dart), the same way event/playlist cover
# presets already work (`Event.COVER_PRESET_CHOICES` /
# `Playlist.COVER_PRESET_CHOICES`).
AVATAR_PRESET_IDS = [str(n) for n in range(1, 12)]  # "1".."11"


def _random_avatar_preset_id():
    """
    Used as `Profile.avatar_preset_id`'s field default, so *every* new
    profile row gets a random preset assigned server-side at creation
    time — regardless of which code path creates it (email verification,
    Google sign-in with no photo, or any other `Profile.objects.
    get_or_create`) — with no separate "assign an avatar" step required
    anywhere. See DECISIONS.md.
    """
    return random.choice(AVATAR_PRESET_IDS)


class Profile(models.Model):

    VISIBILITY_CHOICES = [
        ("public", "Public"),
        ("friends", "Friends Only"),
        ("private", "Private"),
    ]

    AVATAR_TYPE_CHOICES = [
        ("preset", "Preset avatar"),
        ("external_url", "External URL (from social sign-in)"),
        ("custom", "Custom uploaded image"),
    ]

    AVATAR_PRESET_CHOICES = [(preset_id, f"Avatar {preset_id}") for preset_id in AVATAR_PRESET_IDS]

    MUSIC_GENRE_CHOICES = [
        ("pop", "Pop"),
        ("rock", "Rock"),
        ("hip_hop", "Hip-Hop"),
        ("rap", "Rap"),
        ("rnb", "R&B"),
        ("jazz", "Jazz"),
        ("blues", "Blues"),
        ("classical", "Classical"),
        ("electronic", "Electronic"),
        ("house", "House"),
        ("techno", "Techno"),
        ("metal", "Metal"),
        ("punk", "Punk"),
        ("reggae", "Reggae"),
        ("country", "Country"),
        ("folk", "Folk"),
        ("soul", "Soul"),
        ("funk", "Funk"),
        ("indie", "Indie"),
        ("alternative", "Alternative"),
        ("latin", "Latin"),
        ("afrobeat", "Afrobeat"),
        ("kpop", "K-Pop"),
        ("soundtrack", "Soundtrack"),
    ]

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="profile"
    )

    # Public information
    display_name = models.CharField(max_length=50, blank=True)
    bio = models.TextField(max_length=500, blank=True)

    # Friends-only information
    location = models.CharField(max_length=100, blank=True)
    favorite_artist = models.CharField(max_length=100, blank=True)

    # Private information
    phone_number = models.CharField(max_length=30, blank=True)

    # Configurable-visibility information
    birthday = models.DateField(null=True, blank=True)

    # Per-field visibility for the fields above plus "activity" (which
    # gates GET /profile/<id>/activity/ — see UserActivityView). Keyed by
    # "bio", "location", "favorite_artist", "phone_number", "birthday",
    # "activity"; values are one of VISIBILITY_CHOICES. display_name has
    # no entry — it's always public and not user-configurable.
    field_visibility = models.JSONField(default=_default_field_visibility)

    # Avatar — public information (see DECISIONS.md). `avatar_type` says
    # which of the other two to read: `profile_image` for "custom",
    # `avatar_external_url` for "external_url", `avatar_preset_id` for
    # "preset". Exactly one is ever meaningful at a time — `validate()` in
    # `ProfileSerializer` keeps `profile_image`/`avatar_preset_id`
    # mutually exclusive on write, mirroring how `Playlist.cover_image`/
    # `cover_preset` already work.
    avatar_type = models.CharField(max_length=15, choices=AVATAR_TYPE_CHOICES, default="preset")
    avatar_preset_id = models.CharField(
        max_length=10, choices=AVATAR_PRESET_CHOICES, blank=True,
        default=_random_avatar_preset_id,
    )
    avatar_external_url = models.URLField(max_length=500, blank=True, default="")
    profile_image = models.ImageField(
        upload_to="profiles/",
        null=True,
        blank=True
    )

    # Multiple music preferences
    favorite_genres = ArrayField(
        models.CharField(
            max_length=30,
            choices=MUSIC_GENRE_CHOICES
        ),
        default=list,
        blank=True,
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Profile of {self.user.email}"