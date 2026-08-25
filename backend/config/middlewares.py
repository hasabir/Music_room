from channels.security.websocket import WebsocketDenier
from asgiref.sync import sync_to_async
from urllib.parse import parse_qs
import logging

logger = logging.getLogger(__name__)


class JWTAuthMiddlewareStack:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        # Lazy imports to avoid AppRegistryNotReady
        from rest_framework_simplejwt.tokens import AccessToken
        from django.contrib.auth import get_user_model
        User = get_user_model()
        
        scope = self.get_cookies(scope)
        scope['host'] = str(self.get_from_headers(scope, b'host'), encoding='utf-8')
        try:
            token = self.get_token(scope)
            if token:
                access_token_obj = AccessToken(token)
                logger.info(f"Access Token Payload: {access_token_obj.payload}")
                user_id = access_token_obj.get('user_id')  # Assuming 'user_id' is in the token payload
                logger.info(f"User ID: {user_id}")
                user = await sync_to_async(self.get_user)(user_id=user_id, User=User)
                scope['user'] = user
            else:
                raise ValueError('No token found')
        except Exception as e:
            logger.error(f'Error validating token: {e}')
            denier = WebsocketDenier()
            return await denier(scope, receive, send)
        return await self.app(scope, receive, send)

    def get_cookies(self, scope):
        cookies = self.get_from_headers(scope, b'cookie')
        if not cookies:
            return scope
        cookies_arr = cookies.split(b'; ')
        cookies_dict = {}
        for item in cookies_arr:
            key, value = item.split(b'=', 1)
            cookies_dict[str(key, encoding='utf-8')] = str(value, encoding='utf-8')
        scope['cookies'] = cookies_dict
        return scope

    def get_token(self, scope):
        qs = scope['query_string'].decode()
        query_params = parse_qs(qs)
        return query_params.get('token', [None])[0]

    def get_from_headers(self, scope, key):
        headers = scope.get('headers')
        key_tuple = [x for x in headers if x[0] == key]
        if not key_tuple or len(key_tuple) == 0 or len(key_tuple[0]) < 2:
            return None
        return key_tuple[0][1]

    def get_user(self, user_id, User):
        try:
            return User.objects.get(id=user_id)
        except User.DoesNotExist:
            raise ValueError("Invalid user")