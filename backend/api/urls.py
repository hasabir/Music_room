from django.urls import path, include
from api.views import HomeView

urlpatterns = [
    path('', HomeView.as_view(), name='home'),
]