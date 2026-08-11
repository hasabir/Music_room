# authentication/serializers.py
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.utils.http import urlsafe_base64_decode
from django.contrib.auth import authenticate
from .tokens import email_verification_token
from django.utils.encoding import force_str
from rest_framework import serializers
from user.models import User , SocialAccount
from django.conf import settings
from google.auth.transport import requests
from google.oauth2 import id_token

class ResendVerificationSerializer(serializers.Serializer):
    email = serializers.EmailField()

class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ['email', 'password', 'first_name', 'last_name']

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return value

    def create(self, validated_data):
        user = User.objects.create_user(
            email=validated_data['email'],
            password=validated_data['password'],
            first_name=validated_data.get('first_name', ''),
            last_name=validated_data.get('last_name', ''),
            registration_method='email',
        )
        return user


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        email = attrs.get('email')
        password = attrs.get('password')

        user = authenticate(username=email, password=password)
        if not user:
            try:
                user_obj = User.objects.get(email__iexact=email)
            except User.DoesNotExist:
                raise serializers.ValidationError("Invalid email or password.")
            if not user_obj.check_password(password):
                raise serializers.ValidationError("Invalid email or password.")
            user = user_obj

        if not user.is_active:
            raise serializers.ValidationError("This account is disabled.")
        if not user.is_email_verified:
            raise serializers.ValidationError(
                "Please verify your email before logging in."
            )
        attrs['user'] = user
        return attrs

class EmailVerifySerializer(serializers.Serializer):
    uid = serializers.CharField()
    token = serializers.CharField()

    def validate(self, attrs):
        try:
            user_id = force_str(urlsafe_base64_decode(attrs['uid']))
            user = User.objects.get(pk=user_id)
        except (User.DoesNotExist, ValueError, TypeError, OverflowError):
            raise serializers.ValidationError("Invalid verification link.")

        if not email_verification_token.check_token(user, attrs['token']):
            raise serializers.ValidationError("Invalid or expired verification link.")

        attrs['user'] = user
        return attrs


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()


class PasswordResetConfirmSerializer(serializers.Serializer):
    uid = serializers.CharField()
    token = serializers.CharField()
    new_password = serializers.CharField(write_only=True)

    def validate_new_password(self, value):
        validate_password(value)
        return value

    def validate(self, attrs):
        try:
            user_id = force_str(urlsafe_base64_decode(attrs['uid']))
            user = User.objects.get(pk=user_id)
        except (User.DoesNotExist, ValueError, TypeError, OverflowError):
            raise serializers.ValidationError("Invalid reset link.")

        if not default_token_generator.check_token(user, attrs['token']):
            raise serializers.ValidationError("Invalid or expired reset link.")

        attrs['user'] = user
        return attrs


class GoogleLoginSerializer(serializers.Serializer):
    id_token = serializers.CharField()

    def validate(self, attrs):
        google_token = attrs["id_token"]

        try:
            idinfo = id_token.verify_oauth2_token(
                google_token,
                requests.Request(),
                settings.GOOGLE_CLIENT_ID,
            )
        except ValueError:
            raise serializers.ValidationError(
                "Invalid Google ID token."
            )

        # Google must identify the user
        google_uid = idinfo.get("sub")
        email = idinfo.get("email")

        if not google_uid or not email:
            raise serializers.ValidationError(
                "Google account information is incomplete."
            )

        # Google should have verified the email
        if not idinfo.get("email_verified", False):
            raise serializers.ValidationError(
                "Google email is not verified."
            )

        attrs["google_uid"] = google_uid
        attrs["email"] = email
        attrs["first_name"] = idinfo.get("given_name", "")
        attrs["last_name"] = idinfo.get("family_name", "")

        return attrs