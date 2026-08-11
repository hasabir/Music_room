# events/ws_auth.py
"""
Django Channels' built-in AuthMiddlewareStack authenticates via session
cookies, but this project uses JWT tokens everywhere else. This middleware
lets a WebSocket client authenticate the same way it does over REST:
by passing its JWT access token, here as a query parameter, e.g.

    ws://.../ws/events/5/queue/?token=<access_token>
"""
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError


@database_sync_to_async
def get_user_from_token(token):
    from user.models import User
    try:
        access_token = AccessToken(token)
        user_id = access_token["user_id"]
        return User.objects.get(id=user_id)
    except (TokenError, User.DoesNotExist, KeyError):
        return AnonymousUser()


class JWTAuthMiddleware:
    """ASGI middleware that authenticates WebSocket connections via a JWT in the query string."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        query_string = scope.get("query_string", b"").decode()
        query_params = parse_qs(query_string)
        token = query_params.get("token", [None])[0]

        if token:
            scope["user"] = await get_user_from_token(token)
        else:
            scope["user"] = AnonymousUser()

        return await self.app(scope, receive, send)


def JWTAuthMiddlewareStack(app):
    return JWTAuthMiddleware(app)