# user/views.py
from django.conf import settings
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated, IsAdminUser

from user.models import ActionLog
from .serializers import ActionLogSerializer ,UserSerializer


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