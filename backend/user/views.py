# user/views.py
from django.conf import settings
from django.shortcuts import get_object_or_404
from django.utils import timezone
from datetime import timedelta
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny, IsAuthenticated, IsAdminUser

from authentication.utils import log_action
from user.models import ActionLog, Notification, User
from .serializers import ActionLogSerializer, NotificationSerializer, SubscriptionSwitchSerializer, UserSerializer
from .serializers import ClientActionSerializer
from rest_framework.throttling import UserRateThrottle


class ClientActionThrottle(UserRateThrottle):
    rate = '120/min'
    scope = 'client_action'


class ClientActionView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = ClientActionSerializer
    throttle_classes = [ClientActionThrottle]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = request.user if request.user.is_authenticated else None
        log_action(request, 'client.' + serializer.validated_data['action'], user=user)
        return Response(status=status.HTTP_204_NO_CONTENT)


class ActionLogListView(generics.ListAPIView):
    permission_classes = [IsAdminUser]
    serializer_class = ActionLogSerializer

    def get_queryset(self):
        return ActionLog.objects.select_related("user").all()

class MeView(generics.GenericAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = UserSerializer

    def get(self, request):
        return Response(self.get_serializer(request.user).data)

class MyActionLogListView(generics.ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = ActionLogSerializer

    def get_queryset(self):
        return ActionLog.objects.filter(
            user=self.request.user
        ).select_related("user")


class NotificationListView(generics.ListAPIView):
    """Full notification history for the signed-in user, newest first —
    everything `notify_user` has ever recorded for them, not just the
    still-actionable subset (pending friend requests, etc.)."""
    permission_classes = [IsAuthenticated]
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user)


class NotificationMarkReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, notification_id):
        notification = get_object_or_404(Notification, id=notification_id, user=request.user)
        if not notification.is_read:
            notification.is_read = True
            notification.save(update_fields=["is_read"])
        return Response(NotificationSerializer(notification).data)


class NotificationMarkAllReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        Notification.objects.filter(user=request.user, is_read=False).update(is_read=True)
        return Response(status=status.HTTP_204_NO_CONTENT)


class SubscriptionSwitchView(generics.GenericAPIView):
    """Mock upgrade/downgrade — see docs/SUBSCRIPTION_BONUS.md. No payment
    gateway: this just flips the stored tier. Switching to the tier
    you're already on is a no-op 200, not an error."""
    permission_classes = [IsAuthenticated]
    serializer_class = SubscriptionSwitchSerializer
    PREMIUM_PERIOD = timedelta(days=30)

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        new_tier = serializer.validated_data["tier"]
        old_tier = request.user.subscription_tier

        if new_tier == old_tier:
            return Response({
                "user": UserSerializer(request.user).data,
                "detail": f"You are already on the {request.user.get_subscription_tier_display()} plan.",
            })

        request.user.subscription_tier = new_tier
        request.user.subscription_expires_at = (
            timezone.now() + self.PREMIUM_PERIOD if new_tier == User.SUBSCRIPTION_PREMIUM else None
        )
        request.user.save(update_fields=["subscription_tier", "subscription_expires_at"])

        log_action(request, "user.subscription_changed", user=request.user, metadata={
            "from": old_tier,
            "to": new_tier,
        })

        return Response({
            "user": UserSerializer(request.user).data,
            "detail": f"You are now on the {request.user.get_subscription_tier_display()} plan.",
        })
