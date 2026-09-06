# user/urls.py
from django.urls import path
from .views import MeView, ActionLogListView, MyActionLogListView, SubscriptionSwitchView

urlpatterns = [
    path('me/', MeView.as_view(), name='me'),
    path('me/logs', MeView.as_view(), name='me'),
    path("logs/", ActionLogListView.as_view(), name="action-logs"),
    path('subscription/', SubscriptionSwitchView.as_view(), name='subscription-switch'),
]