# user/views.py
from django.conf import settings
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated, IsAdminUser

from authentication.utils import log_action
from user.models import ActionLog
from .serializers import ActionLogSerializer, SubscriptionSwitchSerializer, UserSerializer
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


class SubscriptionSwitchView(generics.GenericAPIView):
    """Mock upgrade/downgrade — see docs/SUBSCRIPTION_BONUS.md. No payment
    gateway: this just flips the stored tier. Switching to the tier
    you're already on is a no-op 200, not an error."""
    permission_classes = [IsAuthenticated]
    serializer_class = SubscriptionSwitchSerializer

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
        request.user.save(update_fields=["subscription_tier"])

        log_action(request, "user.subscription_changed", user=request.user, metadata={
            "from": old_tier,
            "to": new_tier,
        })

        return Response({
            "user": UserSerializer(request.user).data,
            "detail": f"You are now on the {request.user.get_subscription_tier_display()} plan.",
        })
