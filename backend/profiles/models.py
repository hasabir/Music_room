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


class Profile(models.Model):

    VISIBILITY_CHOICES = [
        ("public", "Public"),
        ("friends", "Friends Only"),
        ("private", "Private"),
    ]

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

    # Profile image
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