# config/asgi.py
import os

# STEP 1: Set the settings module FIRST, before any other imports that
# might touch Django models/apps.
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

# STEP 2: Import and call get_asgi_application() SECOND.
# This is what actually calls django.setup() internally and makes the
# app registry ready. NOTHING that imports app code (models, consumers,
# routing, middleware referencing models) can be imported before this line.
from django.core.asgi import get_asgi_application
django_asgi_app = get_asgi_application()

# STEP 3: ONLY NOW is it safe to import anything from your apps
# (events, playlists, channels routing, custom middleware, etc.)
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator

from events.ws_auth import JWTAuthMiddlewareStack
import events.routing
import playlists.routing

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": AllowedHostsOriginValidator(
        JWTAuthMiddlewareStack(
            URLRouter(
                events.routing.websocket_urlpatterns +
                playlists.routing.websocket_urlpatterns
            )
        )
    ),
})