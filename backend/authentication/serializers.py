# authentication/serializers.py
from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password

from user.models import User

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
    """Step 1: user asks for a reset code to be emailed."""
    email = serializers.EmailField()


class PasswordResetVerifyCodeSerializer(serializers.Serializer):
    """Step 2: user enters the code from their email.
    On success, returns a short-lived reset_token instead of the code itself."""
    email = serializers.EmailField()
    code = serializers.CharField(max_length=6)

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

        attrs["otp"] = otp
        attrs["user"] = user
        return attrs


class PasswordResetNewPasswordSerializer(serializers.Serializer):
    """Step 3: user submits their new password using the reset_token from step 2."""
    reset_token = serializers.CharField()
    new_password = serializers.CharField(write_only=True)

    def validate_new_password(self, value):
        validate_password(value)
        return value

    def validate(self, attrs):
        try:
            otp = OTPCode.objects.get(
                reset_token=attrs["reset_token"],
                purpose="password_reset",
                used=False,
            )
        except OTPCode.DoesNotExist:
            raise serializers.ValidationError("Invalid or already-used reset token.")

        if not otp.reset_token_is_valid():
            raise serializers.ValidationError("This reset session has expired. Please start over.")

        attrs["otp"] = otp
        attrs["user"] = otp.user
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

class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()

class ChangePasswordSerializer(serializers.Serializer):
    """For an already-logged-in user changing their own password.
    Requires the current password as proof, unlike the forgot-password flow."""
    old_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True)
 
    def validate_new_password(self, value):
        validate_password(value)
        return value
 
    def validate(self, attrs):
        user = self.context["request"].user
 
        if not user.check_password(attrs["old_password"]):
            raise serializers.ValidationError({"old_password": "Current password is incorrect."})
 
        if attrs["old_password"] == attrs["new_password"]:
            raise serializers.ValidationError({"new_password": "New password must be different from the current password."})
 
        return attrs
 
