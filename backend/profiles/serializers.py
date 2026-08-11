from rest_framework import serializers

from user.models import User
from .models import Friendship , Profile


class FriendSerializer(serializers.ModelSerializer):

    class Meta:
        model = User
        fields = [
            "id",
            "first_name",
            "last_name",
        ]


class FriendshipSerializer(serializers.ModelSerializer):

    sender = FriendSerializer(read_only=True)
    receiver = FriendSerializer(read_only=True)

    class Meta:
        model = Friendship
        fields = [
            "id",
            "sender",
            "receiver",
            "status",
            "created_at",
            "updated_at",
        ]
        read_only_fields = fields


class ProfileSerializer(serializers.ModelSerializer):

    favorite_genres = serializers.ListField(
        child=serializers.ChoiceField(
            choices=Profile.MUSIC_GENRE_CHOICES
        ),
        required=False,
        allow_empty=True,
    )

    class Meta:
        model = Profile
        fields = [
            "id",
            "display_name",
            "bio",
            "location",
            "favorite_artist",
            "phone_number",
            "profile_image",
            "favorite_genres",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "created_at",
            "updated_at",
        ]