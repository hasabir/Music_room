from django.shortcuts import render
from rest_framework import status, generics, permissions
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import authenticate
from django.core.mail import send_mail
from django.conf import settings
from django.utils import timezone
from django.db.models import Q
from drf_spectacular.utils import extend_schema, OpenApiParameter, OpenApiExample
from drf_spectacular.types import OpenApiTypes

from .models import User, Friendship, PasswordResetToken
from .serializers import (
    UserRegistrationSerializer,
    SocialAuthSerializer,
    LinkSocialAccountSerializer,
    EmailVerificationSerializer,
    PasswordResetRequestSerializer,
    PasswordResetConfirmSerializer,
    UserPublicSerializer,
    UserFriendsSerializer,
    UserProfileSerializer,
    UserProfileUpdateSerializer,
    MusicPreferencesSerializer,
    PasswordChangeSerializer,
    FriendshipSerializer,
    FriendRequestSerializer,
    FriendRequestResponseSerializer,
)


def get_tokens_for_user(user):
    """Generate JWT tokens for a user"""
    refresh = RefreshToken.for_user(user)
    return {
        'refresh': str(refresh),
        'access': str(refresh.access_token),
    }


class RegisterView(APIView):
    """Register a new user with email/password"""
    
    permission_classes = [permissions.AllowAny]
    
    @extend_schema(
        tags=['Authentication'],
        request=UserRegistrationSerializer,
        responses={201: UserProfileSerializer},
        description='Register a new user account with email and password'
    )
    def post(self, request):
        serializer = UserRegistrationSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.save()
            
            # Send verification email
            verification_url = f"{request.scheme}://{request.get_host()}/api/auth/verify-email/?token={user.email_verification_token}"
            send_mail(
                'Verify your email - Music Room',
                f'Please click the link to verify your email: {verification_url}',
                settings.DEFAULT_FROM_EMAIL,
                [user.email],
                fail_silently=False,
            )
            
            # Generate tokens
            tokens = get_tokens_for_user(user)
            
            return Response({
                'message': 'User registered successfully. Please check your email to verify your account.',
                'user': UserProfileSerializer(user).data,
                'tokens': tokens
            }, status=status.HTTP_201_CREATED)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class LoginView(APIView):
    """Login with email/password"""
    
    permission_classes = [permissions.AllowAny]
    
    @extend_schema(
        tags=['Authentication'],
        request={
            'type': 'object',
            'properties': {
                'email': {'type': 'string', 'format': 'email'},
                'password': {'type': 'string', 'format': 'password'}
            },
            'required': ['email', 'password']
        },
        responses={200: UserProfileSerializer},
        description='Login with email and password to receive JWT tokens'
    )
    def post(self, request):
        email = request.data.get('email')
        password = request.data.get('password')
        
        if not email or not password:
            return Response({
                'error': 'Please provide both email and password'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        user = authenticate(request, username=email, password=password)
        
        if user is not None:
            if not user.is_active:
                return Response({
                    'error': 'Account is disabled'
                }, status=status.HTTP_403_FORBIDDEN)
            
            tokens = get_tokens_for_user(user)
            
            return Response({
                'message': 'Login successful',
                'user': UserProfileSerializer(user).data,
                'tokens': tokens
            }, status=status.HTTP_200_OK)
        
        return Response({
            'error': 'Invalid credentials'
        }, status=status.HTTP_401_UNAUTHORIZED)


class SocialAuthView(APIView):
    """Authenticate or register user via social provider (Facebook/Google)"""
    
    permission_classes = [permissions.AllowAny]
    
    @extend_schema(
        tags=['Authentication'],
        request=SocialAuthSerializer,
        responses={200: UserProfileSerializer},
        description='Login or register using Facebook or Google OAuth'
    )
    def post(self, request):
        serializer = SocialAuthSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        provider = serializer.validated_data['provider']
        social_id = serializer.validated_data['social_id']
        email = serializer.validated_data['email']
        
        # Try to find user by social ID
        lookup_field = f'{provider}_id'
        user = User.objects.filter(**{lookup_field: social_id}).first()
        
        # If not found, try by email
        if not user:
            user = User.objects.filter(email=email).first()
            
            if user:
                # Link the social account to existing user
                setattr(user, lookup_field, social_id)
                user.email_verified = True  # Social accounts are pre-verified
                user.save()
            else:
                # Create new user
                user = User.objects.create(
                    email=email,
                    **{lookup_field: social_id},
                    email_verified=True,
                    display_name=serializer.validated_data.get('display_name', ''),
                    first_name=serializer.validated_data.get('first_name', ''),
                    last_name=serializer.validated_data.get('last_name', ''),
                )
        
        tokens = get_tokens_for_user(user)
        
        return Response({
            'message': 'Authentication successful',
            'user': UserProfileSerializer(user).data,
            'tokens': tokens
        }, status=status.HTTP_200_OK)


class LinkSocialAccountView(APIView):
    """Link a social account (Facebook/Google) to authenticated user"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    def post(self, request):
        serializer = LinkSocialAccountSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        provider = serializer.validated_data['provider']
        social_id = serializer.validated_data['social_id']
        
        # Check if social ID is already used by another user
        lookup_field = f'{provider}_id'
        existing_user = User.objects.filter(**{lookup_field: social_id}).exclude(id=request.user.id).first()
        
        if existing_user:
            return Response({
                'error': f'This {provider} account is already linked to another user'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Link the account
        setattr(request.user, lookup_field, social_id)
        request.user.save()
        
        return Response({
            'message': f'{provider.capitalize()} account linked successfully',
            'user': UserProfileSerializer(request.user).data
        }, status=status.HTTP_200_OK)


class VerifyEmailView(APIView):
    """Verify user's email address"""
    
    permission_classes = [permissions.AllowAny]
    
    def get(self, request):
        token = request.query_params.get('token')
        
        if not token:
            return Response({
                'error': 'Token is required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            user = User.objects.get(email_verification_token=token)
            user.email_verified = True
            user.save()
            
            return Response({
                'message': 'Email verified successfully'
            }, status=status.HTTP_200_OK)
        except User.DoesNotExist:
            return Response({
                'error': 'Invalid verification token'
            }, status=status.HTTP_400_BAD_REQUEST)


class ResendVerificationEmailView(APIView):
    """Resend email verification link"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    def post(self, request):
        user = request.user
        
        if user.email_verified:
            return Response({
                'message': 'Email is already verified'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Send verification email
        verification_url = f"{request.scheme}://{request.get_host()}/api/auth/verify-email/?token={user.email_verification_token}"
        send_mail(
            'Verify your email - Music Room',
            f'Please click the link to verify your email: {verification_url}',
            settings.DEFAULT_FROM_EMAIL,
            [user.email],
            fail_silently=False,
        )
        
        return Response({
            'message': 'Verification email sent'
        }, status=status.HTTP_200_OK)


class PasswordResetRequestView(APIView):
    """Request password reset email"""
    
    permission_classes = [permissions.AllowAny]
    
    @extend_schema(
        tags=['Authentication'],
        request=PasswordResetRequestSerializer,
        responses={200: {'type': 'object', 'properties': {'message': {'type': 'string'}}}},
        description='Request a password reset email'
    )
    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        email = serializer.validated_data['email']
        
        try:
            user = User.objects.get(email=email)
            
            # Create reset token
            reset_token = PasswordResetToken.objects.create(user=user)
            
            # Send reset email
            reset_url = f"{request.scheme}://{request.get_host()}/reset-password?token={reset_token.token}"
            send_mail(
                'Password Reset - Music Room',
                f'Click the link to reset your password: {reset_url}\n\nThis link will expire in 24 hours.',
                settings.DEFAULT_FROM_EMAIL,
                [user.email],
                fail_silently=False,
            )
            
            return Response({
                'message': 'Password reset email sent'
            }, status=status.HTTP_200_OK)
        except User.DoesNotExist:
            # Return success even if user doesn't exist (security best practice)
            return Response({
                'message': 'Password reset email sent'
            }, status=status.HTTP_200_OK)


class PasswordResetConfirmView(APIView):
    """Confirm password reset with token"""
    
    permission_classes = [permissions.AllowAny]
    
    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        token = serializer.validated_data['token']
        new_password = serializer.validated_data['new_password']
        
        try:
            reset_token = PasswordResetToken.objects.get(token=token)
            
            if not reset_token.is_valid():
                return Response({
                    'error': 'Token has expired or already been used'
                }, status=status.HTTP_400_BAD_REQUEST)
            
            # Reset password
            user = reset_token.user
            user.set_password(new_password)
            user.save()
            
            # Mark token as used
            reset_token.used = True
            reset_token.save()
            
            return Response({
                'message': 'Password reset successfully'
            }, status=status.HTTP_200_OK)
        except PasswordResetToken.DoesNotExist:
            return Response({
                'error': 'Invalid reset token'
            }, status=status.HTTP_400_BAD_REQUEST)


class PasswordChangeView(APIView):
    """Change password for authenticated user"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    @extend_schema(
        tags=['Authentication'],
        request=PasswordChangeSerializer,
        responses={200: {'type': 'object', 'properties': {'message': {'type': 'string'}}}},
        description='Change password for authenticated user'
    )
    def post(self, request):
        serializer = PasswordChangeSerializer(data=request.data, context={'request': request})
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        user = request.user
        user.set_password(serializer.validated_data['new_password'])
        user.save()
        
        return Response({
            'message': 'Password changed successfully'
        }, status=status.HTTP_200_OK)


class UserProfileView(APIView):
    """Get or update user profile"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    @extend_schema(
        tags=['Profile'],
        responses={200: UserProfileSerializer},
        description='Get current user profile information'
    )
    def get(self, request):
        serializer = UserProfileSerializer(request.user)
        return Response(serializer.data, status=status.HTTP_200_OK)
    
    def patch(self, request):
        serializer = UserProfileUpdateSerializer(
            request.user,
            data=request.data,
            partial=True
        )
        if serializer.is_valid():
            serializer.save()
            return Response({
                'message': 'Profile updated successfully',
                'user': UserProfileSerializer(request.user).data
            }, status=status.HTTP_200_OK)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class MusicPreferencesView(APIView):
    """Get or update music preferences"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request):
        serializer = MusicPreferencesSerializer(request.user)
        return Response(serializer.data, status=status.HTTP_200_OK)
    
    def patch(self, request):
        serializer = MusicPreferencesSerializer(
            request.user,
            data=request.data,
            partial=True
        )
        if serializer.is_valid():
            serializer.save()
            return Response({
                'message': 'Music preferences updated successfully',
                'preferences': serializer.data
            }, status=status.HTTP_200_OK)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class UserDetailView(APIView):
    """Get public or friends-only information about a user"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request, user_id):
        try:
            user = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return Response({
                'error': 'User not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Check if users are friends
        are_friends = Friendship.objects.filter(
            Q(from_user=request.user, to_user=user, status='accepted') |
            Q(from_user=user, to_user=request.user, status='accepted')
        ).exists()
        
        # Return appropriate level of information
        if user.id == request.user.id:
            serializer = UserProfileSerializer(user)
        elif are_friends:
            serializer = UserFriendsSerializer(user)
        else:
            serializer = UserPublicSerializer(user)
        
        return Response(serializer.data, status=status.HTTP_200_OK)


class SendFriendRequestView(APIView):
    """Send a friend request"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    def post(self, request):
        serializer = FriendRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        to_user_email = serializer.validated_data['to_user_email']
        
        # Get target user
        try:
            to_user = User.objects.get(email=to_user_email)
        except User.DoesNotExist:
            return Response({
                'error': 'User not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Check if trying to add self
        if to_user.id == request.user.id:
            return Response({
                'error': 'You cannot send a friend request to yourself'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if friendship already exists
        existing_friendship = Friendship.objects.filter(
            Q(from_user=request.user, to_user=to_user) |
            Q(from_user=to_user, to_user=request.user)
        ).first()
        
        if existing_friendship:
            return Response({
                'error': f'Friend request already {existing_friendship.status}'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Create friend request
        friendship = Friendship.objects.create(
            from_user=request.user,
            to_user=to_user,
            status='pending'
        )
        
        return Response({
            'message': 'Friend request sent',
            'friendship': FriendshipSerializer(friendship).data
        }, status=status.HTTP_201_CREATED)


class RespondToFriendRequestView(APIView):
    """Accept, reject, or block a friend request"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    def post(self, request, friendship_id):
        serializer = FriendRequestResponseSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        action = serializer.validated_data['action']
        
        try:
            friendship = Friendship.objects.get(
                id=friendship_id,
                to_user=request.user,
                status='pending'
            )
        except Friendship.DoesNotExist:
            return Response({
                'error': 'Friend request not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        if action == 'accept':
            friendship.status = 'accepted'
        elif action == 'reject':
            friendship.status = 'rejected'
        elif action == 'block':
            friendship.status = 'blocked'
        
        friendship.save()
        
        return Response({
            'message': f'Friend request {action}ed',
            'friendship': FriendshipSerializer(friendship).data
        }, status=status.HTTP_200_OK)


class FriendListView(APIView):
    """Get list of friends"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request):
        friendships = Friendship.objects.filter(
            Q(from_user=request.user, status='accepted') |
            Q(to_user=request.user, status='accepted')
        )
        
        # Extract friend users
        friends = []
        for friendship in friendships:
            friend = friendship.to_user if friendship.from_user == request.user else friendship.from_user
            friends.append(friend)
        
        serializer = UserFriendsSerializer(friends, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class FriendRequestsListView(APIView):
    """Get list of pending friend requests"""
    
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request):
        # Received requests
        received_requests = Friendship.objects.filter(
            to_user=request.user,
            status='pending'
        )
        
        # Sent requests
        sent_requests = Friendship.objects.filter(
            from_user=request.user,
            status='pending'
        )
        
        return Response({
            'received': FriendshipSerializer(received_requests, many=True).data,
            'sent': FriendshipSerializer(sent_requests, many=True).data
        }, status=status.HTTP_200_OK)

