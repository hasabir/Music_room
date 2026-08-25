from rest_framework import serializers
from django.contrib.auth import authenticate
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from .models import User, Friendship, PasswordResetToken


class UserRegistrationSerializer(serializers.ModelSerializer):
    """Serializer for user registration with email/password"""
    
    password = serializers.CharField(
        write_only=True,
        required=True,
        validators=[validate_password],
        style={'input_type': 'password'}
    )
    password_confirm = serializers.CharField(
        write_only=True,
        required=True,
        style={'input_type': 'password'}
    )
    
    class Meta:
        model = User
        fields = [
            'email', 'password', 'password_confirm',
            'display_name', 'first_name', 'last_name'
        ]
        extra_kwargs = {
            'first_name': {'required': False},
            'last_name': {'required': False},
        }
    
    def validate(self, attrs):
        """Validate that passwords match"""
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError({
                "password": "Password fields didn't match."
            })
        return attrs
    
    def create(self, validated_data):
        """Create a new user"""
        validated_data.pop('password_confirm')
        user = User.objects.create_user(**validated_data)
        return user


class SocialAuthSerializer(serializers.Serializer):
    """Serializer for social authentication (Facebook, Google)"""
    
    provider = serializers.ChoiceField(choices=['facebook', 'google'])
    access_token = serializers.CharField()
    email = serializers.EmailField()
    social_id = serializers.CharField()
    first_name = serializers.CharField(required=False, allow_blank=True)
    last_name = serializers.CharField(required=False, allow_blank=True)
    display_name = serializers.CharField(required=False, allow_blank=True)


class LinkSocialAccountSerializer(serializers.Serializer):
    """Serializer for linking social accounts to existing user"""
    
    provider = serializers.ChoiceField(choices=['facebook', 'google'])
    social_id = serializers.CharField()
    access_token = serializers.CharField()


class EmailVerificationSerializer(serializers.Serializer):
    """Serializer for email verification"""
    
    token = serializers.UUIDField()


class PasswordResetRequestSerializer(serializers.Serializer):
    """Serializer for requesting password reset"""
    
    email = serializers.EmailField()


class PasswordResetConfirmSerializer(serializers.Serializer):
    """Serializer for confirming password reset"""
    
    token = serializers.UUIDField()
    new_password = serializers.CharField(
        write_only=True,
        validators=[validate_password],
        style={'input_type': 'password'}
    )
    new_password_confirm = serializers.CharField(
        write_only=True,
        style={'input_type': 'password'}
    )
    
    def validate(self, attrs):
        """Validate that passwords match"""
        if attrs['new_password'] != attrs['new_password_confirm']:
            raise serializers.ValidationError({
                "new_password": "Password fields didn't match."
            })
        return attrs


class UserPublicSerializer(serializers.ModelSerializer):
    """Serializer for public user information (visible to all)"""
    
    class Meta:
        model = User
        fields = ['id', 'email', 'display_name', 'avatar', 'bio']
        read_only_fields = fields


class UserFriendsSerializer(serializers.ModelSerializer):
    """Serializer for friends-only information"""
    
    class Meta:
        model = User
        fields = [
            'id', 'email', 'display_name', 'avatar', 'bio',
            'phone_number', 'location'
        ]
        read_only_fields = fields


class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer for user's own profile (full information)"""
    
    class Meta:
        model = User
        fields = [
            'id', 'email', 'display_name', 'avatar', 'bio',
            'first_name', 'last_name', 'phone_number', 'location',
            'date_of_birth', 'favorite_genres', 'favorite_artists',
            'music_services', 'subscription_type', 'subscription_expires_at',
            'email_verified', 'facebook_id', 'google_id',
            'created_at', 'updated_at'
        ]
        read_only_fields = [
            'id', 'email', 'email_verified', 'subscription_expires_at',
            'created_at', 'updated_at'
        ]


class UserProfileUpdateSerializer(serializers.ModelSerializer):
    """Serializer for updating user profile"""
    
    class Meta:
        model = User
        fields = [
            'display_name', 'avatar', 'bio', 'first_name', 'last_name',
            'phone_number', 'location', 'date_of_birth',
            'favorite_genres', 'favorite_artists', 'music_services'
        ]


class MusicPreferencesSerializer(serializers.ModelSerializer):
    """Serializer for updating music preferences"""
    
    class Meta:
        model = User
        fields = ['favorite_genres', 'favorite_artists', 'music_services']


class PasswordChangeSerializer(serializers.Serializer):
    """Serializer for changing password"""
    
    old_password = serializers.CharField(
        write_only=True,
        required=True,
        style={'input_type': 'password'}
    )
    new_password = serializers.CharField(
        write_only=True,
        required=True,
        validators=[validate_password],
        style={'input_type': 'password'}
    )
    new_password_confirm = serializers.CharField(
        write_only=True,
        required=True,
        style={'input_type': 'password'}
    )
    
    def validate(self, attrs):
        """Validate that new passwords match"""
        if attrs['new_password'] != attrs['new_password_confirm']:
            raise serializers.ValidationError({
                "new_password": "Password fields didn't match."
            })
        return attrs
    
    def validate_old_password(self, value):
        """Validate that old password is correct"""
        user = self.context['request'].user
        if not user.check_password(value):
            raise serializers.ValidationError("Old password is incorrect.")
        return value


class FriendshipSerializer(serializers.ModelSerializer):
    """Serializer for friendship requests"""
    
    from_user = UserPublicSerializer(read_only=True)
    to_user = UserPublicSerializer(read_only=True)
    
    class Meta:
        model = Friendship
        fields = ['id', 'from_user', 'to_user', 'status', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']


class FriendRequestSerializer(serializers.Serializer):
    """Serializer for sending friend requests"""
    
    to_user_email = serializers.EmailField()


class FriendRequestResponseSerializer(serializers.Serializer):
    """Serializer for responding to friend requests"""
    
    action = serializers.ChoiceField(choices=['accept', 'reject', 'block'])
