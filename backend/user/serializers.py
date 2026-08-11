# user/serializers.py
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.utils.http import urlsafe_base64_decode
from django.contrib.auth import authenticate
from django.utils.encoding import force_str
from rest_framework import serializers
from django.conf import settings
from user.models import User
from user.models import ActionLog


class ActionLogSerializer(serializers.ModelSerializer):
    user_email = serializers.EmailField(
        source="user.email",
        read_only=True
    )

    class Meta:
        model = ActionLog
        fields = [
            "id",
            "user",
            "user_email",
            "action",
            "platform",
            "device",
            "app_version",
            "ip_address",
            "created_at",
        ]
        read_only_fields = fields

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'email', 'first_name', 'last_name', 'registration_method', 'is_email_verified', 'date_joined']
        read_only_fields = fields

