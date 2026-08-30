# profile/views.py
from django.shortcuts import get_object_or_404
from django.db.models import Q

from rest_framework import generics, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from drf_spectacular.utils import extend_schema, extend_schema_view, OpenApiResponse

from user.models import User, ActionLog
from authentication.utils import log_action

from .models import Friendship, Profile, _default_field_visibility
from .serializers import (
    FriendSerializer,
    FriendshipSerializer,
    ProfileSerializer,
    ActivityLogSerializer,
)


def _are_friends(user_a, user_b):
    return Friendship.objects.filter(
        status="accepted"
    ).filter(
        Q(sender=user_a, receiver=user_b) |
        Q(sender=user_b, receiver=user_a)
    ).exists()


def _is_visible(tier, is_friend):
    return tier == "public" or (tier == "friends" and is_friend)


def _activity_queryset_for(target_user, viewer):
    """
    Activity visible to `viewer` about `target_user`:
    - the owner sees everything.
    - if `target_user` set their "activity" field visibility to "private",
      nobody but the owner sees anything.
    - if set to "friends", only friends see anything (everyone else gets
      an empty queryset).
    - friends always see everything (public and private rooms/playlists).
    - otherwise (public tier, non-friend viewer), only activity tied to
      public rooms/playlists is visible — entries whose
      metadata["visibility"] == "private" are excluded.
    """
    qs = ActionLog.objects.filter(
        user=target_user
    ).filter(
        Q(action__startswith="event.") | Q(action__startswith="playlist.")
    )

    if viewer.id == target_user.id:
        return qs

    is_friend = _are_friends(viewer, target_user)
    if is_friend:
        return qs

    profile, _ = Profile.objects.get_or_create(user=target_user)
    tier = profile.field_visibility.get("activity", _default_field_visibility()["activity"])
    if tier in ("friends", "private"):
        return qs.none()

    return qs.exclude(metadata__visibility="private")


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


@extend_schema(
    summary="List my sent friend requests",
    description="Returns friend requests you've sent that are still awaiting the other person's response.",
    responses={200: FriendshipSerializer(many=True)},
    tags=["profile"],
)
class SentFriendRequestListView(generics.ListAPIView):

    permission_classes = [IsAuthenticated]
    serializer_class = FriendshipSerializer

    def get_queryset(self):

        return Friendship.objects.filter(
            sender=self.request.user,
            status="pending"
        ).select_related(
            "sender",
            "receiver"
        )


@extend_schema(
    summary="Search users",
    description=(
        "Searches users by username, first name, or last name (case-insensitive, "
        "partial match). Excludes yourself. Each result includes your "
        "relationship status with that user (`none`, `pending_sent`, "
        "`pending_received`, or `friends`), plus the `friendship_id` when one "
        "exists, so pending requests can be accepted/rejected directly from "
        "search results."
    ),
    responses={200: OpenApiResponse(description="List of matching users with relationship_status.")},
    tags=["profile"],
)
class UserSearchView(generics.GenericAPIView):

    permission_classes = [IsAuthenticated]

    def get(self, request):

        query = request.query_params.get("q", "").strip()
        if not query:
            return Response([])

        users = list(User.objects.filter(
            Q(username__icontains=query) |
            Q(first_name__icontains=query) |
            Q(last_name__icontains=query)
        ).exclude(id=request.user.id)[:20])

        sent = {
            f.receiver_id: f
            for f in Friendship.objects.filter(sender=request.user, receiver__in=users)
        }
        received = {
            f.sender_id: f
            for f in Friendship.objects.filter(receiver=request.user, sender__in=users)
        }

        results = []
        for user in users:
            sent_f = sent.get(user.id)
            received_f = received.get(user.id)

            if sent_f and sent_f.status == "accepted":
                relationship, friendship_id = "friends", sent_f.id
            elif received_f and received_f.status == "accepted":
                relationship, friendship_id = "friends", received_f.id
            elif sent_f and sent_f.status == "pending":
                relationship, friendship_id = "pending_sent", sent_f.id
            elif received_f and received_f.status == "pending":
                relationship, friendship_id = "pending_received", received_f.id
            else:
                relationship, friendship_id = "none", None

            results.append({
                "id": user.id,
                "username": user.username,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "relationship_status": relationship,
                "friendship_id": friendship_id,
            })

        return Response(results)


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
        "- `display_name`, `profile_image`, `avatar`, `avatar_type`, "
        "`favorite_genres`, `votes_count`, and `playlists_count` are "
        "always returned — avatar is public information.\n"
        "- `bio`, `location`, `favorite_artist`, `phone_number`, and "
        "`birthday` are each returned only if their tier in "
        "`field_visibility` is "
        "'public', or 'friends' and you're friends with the target user; "
        "otherwise the key is omitted entirely. See `PATCH /profile/me/` "
        "to change your own tiers."
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

        is_friend = _are_friends(request.user, target_user)

        serialized = ProfileSerializer(profile).data

        data = {
            "display_name": profile.display_name,
            "profile_image": profile.profile_image.url if profile.profile_image else None,
            "avatar": serialized["avatar"],
            "avatar_type": serialized["avatar_type"],
            "favorite_genres": profile.favorite_genres,
            "votes_count": serialized["votes_count"],
            "playlists_count": serialized["playlists_count"],
        }

        defaults = _default_field_visibility()
        visibility = profile.field_visibility
        field_values = {
            "bio": profile.bio,
            "location": profile.location,
            "favorite_artist": profile.favorite_artist,
            "phone_number": profile.phone_number,
            "birthday": profile.birthday,
        }
        for field, value in field_values.items():
            tier = visibility.get(field, defaults[field])
            if _is_visible(tier, is_friend):
                data[field] = value

        log_action(request, "profile.viewed", user=request.user)
        return Response(data)


@extend_schema(
    summary="List my recent activity",
    description=(
        "Returns your recent activity related to votes, rooms (events), "
        "and playlists — e.g. casting/retracting a vote, creating a room, "
        "adding a song to a room's queue, creating a playlist, adding a "
        "song to a playlist, inviting/removing a playlist collaborator. "
        "Newest first."
    ),
    responses={200: ActivityLogSerializer(many=True)},
    tags=["profile"],
)
class MyActivityView(generics.ListAPIView):

    permission_classes = [IsAuthenticated]
    serializer_class = ActivityLogSerializer

    def get_queryset(self):
        return _activity_queryset_for(self.request.user, self.request.user)


@extend_schema(
    summary="List another user's recent activity",
    description=(
        "Returns another user's recent activity, filtered by visibility:\n\n"
        "- If you are viewing your own activity, everything is returned.\n"
        "- If you are friends with the target user, everything is returned "
        "(including activity tied to private rooms/playlists).\n"
        "- Otherwise, the target user's `field_visibility.activity` tier "
        "(see `Profile`/`PATCH /profile/me/`) decides: 'private' or "
        "'friends' returns nothing, 'public' (the default) returns only "
        "activity tied to public rooms/playlists."
    ),
    responses={200: ActivityLogSerializer(many=True)},
    tags=["profile"],
)
class UserActivityView(generics.ListAPIView):

    permission_classes = [IsAuthenticated]
    serializer_class = ActivityLogSerializer

    def get_queryset(self):
        target_user = get_object_or_404(User, id=self.kwargs["user_id"])
        return _activity_queryset_for(target_user, self.request.user)
