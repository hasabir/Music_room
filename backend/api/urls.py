from django.urls import path, include
from api.views import HomeView
from drf_spectacular.views import SpectacularAPIView, SpectacularRedocView, SpectacularSwaggerView
urlpatterns = [
    # path('', HomeView.as_view(), name='home'),
    path('auth/',include("authentication.urls")),
    path('user/',include("user.urls")),
    path('profile/',include("profiles.urls")),
    path('events/', include('events.urls')),
    path('playlists/', include('playlists.urls')),
    # ----------
    path('schema/', SpectacularAPIView.as_view(), name='schema'),
    path('',
         SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
]