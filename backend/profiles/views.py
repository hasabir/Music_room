# profile/views.py
from django.shortcuts import get_object_or_404
from django.db.models import Q

from rest_framework import generics, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse

from user.models import User
from authentication.utils import log_action

from .models import Friendship, Profile
from .serializers import FriendSerializer, FriendshipSerializer, ProfileSerializer


@extend_schema(
    summary="Send a friend request",
    description="Sends a friend request to another user. Fails if already friends, or if a request already exists in either direction.",
    responses={
        201: FriendshipSerializer,
        400: OpenApiResponse(description="Cannot friend yourself, already friends, or a request already exists."),
    },
    tags=["profile"],
)
class SendFriendRequestView(generics.GenericAPIView):

    permission_classes = [IsAuthenticated]

    def post(self, request, user_id):

        if request.user.id == user_id:
            return Response(
                {"detail": "You cannot add yourself as a friend."},
                status=status.HTTP_400_BAD_REQUEST
            )

        receiver = get_object_or_404(User, id=user_id)

        existing = Friendship.objects.filter(
            sender=request.user,
            receiver=receiver
        ).first()

        if existing:

            if existing.status == "accepted":
                return Response(
                    {"detail": "You are already friends."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if existing.status == "pending":
                return Response(
                    {"detail": "Friend request already sent."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        reverse = Friendship.objects.filter(
            sender=receiver,
            receiver=request.user
        ).first()

        if reverse:

            if reverse.status == "accepted":
                return Response(
                    {"detail": "You are already friends."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if reverse.status == "pending":
                return Response(
                    {"detail": "This user already sent you a friend request."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        friendship = Friendship.objects.create(
            sender=request.user,
            receiver=receiver,
            status="pending"
        )

        log_action(
            request,
            "friend.request_sent",
            user=request.user
        )

        return Response(
            FriendshipSerializer(friendship).data,
            status=status.HTTP_201_CREATED
        )


@extend_schema(
    summary="Accept a friend request",
    description="Accepts a pending friend request sent to you.",
    responses={
        200: FriendshipSerializer,
        404: OpenApiResponse(description="No matching pending request found."),
    },
    tags=["profile"],
)
class AcceptFriendRequestView(generics.GenericAPIView):

    permission_classes = [IsAuthenticated]

    def post(self, request, request_id):

        friendship = get_object_or_404(
            Friendship,
            id=request_id,
            receiver=request.user,
            status="pending"
        )

        friendship.status = "accepted"
        friendship.save(
            update_fields=["status", "updated_at"]
        )

        log_action(
            request,
            "friend.request_accepted",
            user=request.user
        )

        return Response(
            FriendshipSerializer(friendship).data,
            status=status.HTTP_200_OK
        )


@extend_schema(
    summary="Reject a friend request",
    description="Rejects a pending friend request sent to you.",
    responses={
        200: OpenApiResponse(description="Friend request rejected."),
        404: OpenApiResponse(description="No matching pending request found."),
    },
    tags=["profile"],
)
class RejectFriendRequestView(generics.GenericAPIView):

    permission_classes = [IsAuthenticated]

    def post(self, request, request_id):

        friendship = get_object_or_404(
            Friendship,
            id=request_id,
            receiver=request.user,
            status="pending"
        )

        friendship.status = "rejected"
        friendship.save(
            update_fields=["status", "updated_at"]
        )

        log_action(
            request,
            "friend.request_rejected",
            user=request.user
        )

        return Response(
            {"detail": "Friend request rejected."},
            status=status.HTTP_200_OK
        )


@extend_schema(
    summary="Remove a friend",
    description="Removes an existing (accepted) friendship with another user, regardless of who originally sent the request.",
    responses={
        204: OpenApiResponse(description="Friend removed successfully."),
        404: OpenApiResponse(description="You are not friends with this user."),
    },
    tags=["profile"],
)
class RemoveFriendView(generics.GenericAPIView):

    permission_classes = [IsAuthenticated]

    def delete(self, request, user_id):

        friendship = Friendship.objects.filter(
            status="accepted"
        ).filter(
            sender=request.user,
            receiver_id=user_id
        ).first()

        if not friendship:
            friendship = Friendship.objects.filter(
                status="accepted"
            ).filter(
                sender_id=user_id,
                receiver=request.user
            ).first()

        if not friendship:
            return Response(
                {"detail": "You are not friends with this user."},
                status=status.HTTP_404_NOT_FOUND
            )

        friendship.delete()

        log_action(
            request,
            "friend.removed",
            user=request.user
        )

        return Response(
            {"detail": "Friend removed successfully."},
            status=status.HTTP_204_NO_CONTENT
        )


@extend_schema(
    summary="List my friends",
    description="Returns the list of users you are currently friends with (accepted friendships only, either direction).",
    responses={200: FriendSerializer(many=True)},
    tags=["profile"],
)
class FriendListView(generics.ListAPIView):

    permission_classes = [IsAuthenticated]
    serializer_class = FriendSerializer

    def get_queryset(self):

        user = self.request.user

        sent = Friendship.objects.filter(
            sender=user,
            status="accepted"
        ).values_list(
            "receiver_id",
            flat=True
        )

        received = Friendship.objects.filter(
            receiver=user,
            status="accepted"
        ).values_list(
            "sender_id",
            flat=True
        )

        return User.objects.filter(
            id__in=list(sent) + list(received)
        )


@extend_schema(
    summary="List pending friend requests",
    description="Returns friend requests sent to you that are still pending your response.",
    responses={200: FriendshipSerializer(many=True)},
    tags=["profile"],
)
class PendingFriendRequestListView(generics.ListAPIView):

    permission_classes = [IsAuthenticated]
    serializer_class = FriendshipSerializer

    def get_queryset(self):

        return Friendship.objects.filter(
            receiver=self.request.user,
            status="pending"
        ).select_related(
            "sender",
            "receiver"
        )


@extend_schema_view(
    get=extend_schema(
        summary="Get my full profile",
        description="Returns your own profile with all fields visible (public, friends-only, and private).",
        responses={200: ProfileSerializer},
        tags=["profile"],
    ),
    put=extend_schema(
        summary="Update my full profile",
        description="Full update of your profile. Only the current user's own profile can be edited this way.",
        request=ProfileSerializer,
        responses={200: ProfileSerializer},
        tags=["profile"],
    ),
    patch=extend_schema(
        summary="Partially update my profile",
        description="Update one or more fields of your profile without resending the whole object.",
        request=ProfileSerializer,
        responses={200: ProfileSerializer},
        tags=["profile"],
    ),
)
class MyProfileView(generics.RetrieveUpdateAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = ProfileSerializer

    def get_object(self):
        profile, created = Profile.objects.get_or_create(
            user=self.request.user
        )
        return profile


@extend_schema(
    summary="View another user's profile",
    description=(
        "Returns another user's profile, filtered by visibility tier:\n\n"
        "- If you are viewing your own profile, all fields are returned.\n"
        "- If you are friends with the target user, public + friends-only "
        "fields are returned.\n"
        "- Otherwise, only public fields are returned.\n\n"
        "Private fields (e.g. phone number) are never returned here — "
        "only visible via `GET /profile/me/`."
    ),
    responses={200: OpenApiResponse(description="Profile data, filtered according to visibility rules above.")},
    tags=["profile"],
)
class UserProfileView(generics.GenericAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        target_user = get_object_or_404(User, id=user_id)
        profile, _ = Profile.objects.get_or_create(user=target_user)

        if request.user.id == target_user.id:
            return Response(ProfileSerializer(profile).data)

        is_friend = Friendship.objects.filter(
            status="accepted"
        ).filter(
            Q(sender=request.user, receiver=target_user) |
            Q(sender=target_user, receiver=request.user)
        ).exists()

        data = {
            "display_name": profile.display_name,
            "bio": profile.bio,
            "profile_image": profile.profile_image.url if profile.profile_image else None,
            "favorite_genres": profile.favorite_genres,
        }

        if is_friend:
            data["location"] = profile.location
            data["favorite_artist"] = profile.favorite_artist

        log_action(request, "profile.viewed", user=request.user)
        return Response(data)