from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import generics, serializers
from rest_framework.permissions import IsAuthenticated

class HomeView(APIView):
    def get(self, request):
        return Response({'Details': 'Api is Alive!'})