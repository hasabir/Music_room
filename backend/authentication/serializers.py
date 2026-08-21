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
from .models import OTPCode

class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ["email", "password", "first_name", "last_name"]

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return value

    def create(self, validated_data):
        user = User.objects.create_user(
            email=validated_data["email"],
            password=validated_data["password"],
            first_name=validated_data.get("first_name", ""),
            last_name=validated_data.get("last_name", ""),
            registration_method="email",
        )
        return user


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        email = attrs.get("email")
        password = attrs.get("password")

        try:
            user = User.objects.get(email__iexact=email)
        except User.DoesNotExist:
            raise serializers.ValidationError({"detail": "Invalid email or password."})

        if not user.check_password(password):
            raise serializers.ValidationError({"detail": "Invalid email or password."})

        if not user.is_active:
            raise serializers.ValidationError({"detail": "This account is disabled."})

        if user.registration_method == "email" and not user.is_email_verified:
            raise serializers.ValidationError({
                "detail": "Email not verified. Please verify your email before logging in.",
                "code": "email_not_verified"
            })

        attrs["user"] = user
        return attrs


class EmailVerifySerializer(serializers.Serializer):
    email = serializers.EmailField()
    code = serializers.CharField(max_length=6)

    def validate(self, attrs):
        try:
            user = User.objects.get(email__iexact=attrs["email"])
        except User.DoesNotExist:
            raise serializers.ValidationError("Invalid email or code.")

        try:
            otp = OTPCode.objects.get(
                user=user, code=attrs["code"], purpose="verify_email", used=False
            )
        except OTPCode.DoesNotExist:
            raise serializers.ValidationError("Invalid or already-used code.")

        if not otp.is_valid():
            raise serializers.ValidationError("This code has expired.")

        otp.used = True
        otp.save(update_fields=["used"])

        attrs["user"] = user
        return attrs


class ResendVerificationSerializer(serializers.Serializer):
    email = serializers.EmailField()


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()


class PasswordResetConfirmSerializer(serializers.Serializer):
    email = serializers.EmailField()
    code = serializers.CharField(max_length=6)
    new_password = serializers.CharField(write_only=True)

    def validate_new_password(self, value):
        validate_password(value)
        return value

    def validate(self, attrs):
        try:
            user = User.objects.get(email__iexact=attrs["email"])
        except User.DoesNotExist:
            raise serializers.ValidationError("Invalid email or code.")

        try:
            otp = OTPCode.objects.get(
                user=user, code=attrs["code"], purpose="password_reset", used=False
            )
        except OTPCode.DoesNotExist:
            raise serializers.ValidationError("Invalid or already-used code.")

        if not otp.is_valid():
            raise serializers.ValidationError("This code has expired.")

        otp.used = True
        otp.save(update_fields=["used"])

        attrs["user"] = user
        return attrs


class GoogleLoginSerializer(serializers.Serializer):
    id_token = serializers.CharField()

    def validate(self, attrs):
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests
        from django.conf import settings

        google_token = attrs["id_token"]

        try:
            idinfo = google_id_token.verify_oauth2_token(
                google_token,
                google_requests.Request(),
                settings.GOOGLE_CLIENT_ID,
            )
        except ValueError:
            raise serializers.ValidationError("Invalid Google ID token.")

        google_uid = idinfo.get("sub")
        email = idinfo.get("email")

        if not google_uid or not email:
            raise serializers.ValidationError("Google account information is incomplete.")

        if not idinfo.get("email_verified", False):
            raise serializers.ValidationError("Google email is not verified.")

        attrs["google_uid"] = google_uid
        attrs["email"] = email
        attrs["first_name"] = idinfo.get("given_name", "")
        attrs["last_name"] = idinfo.get("family_name", "")

        return attrs