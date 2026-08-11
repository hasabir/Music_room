# authentication/throttles.py
from rest_framework.throttling import SimpleRateThrottle


class LoginRateThrottle(SimpleRateThrottle):
    scope = 'login'

    def get_cache_key(self, request, view):
        # throttle by IP for unauthenticated login attempts
        return self.cache_format % {
            'scope': self.scope,
            'ident': self.get_ident(request)
        }


class RegisterRateThrottle(SimpleRateThrottle):
    scope = 'register'

    def get_cache_key(self, request, view):
        return self.cache_format % {
            'scope': self.scope,
            'ident': self.get_ident(request)
        }


class PasswordResetRateThrottle(SimpleRateThrottle):
    scope = 'password_reset'

    def get_cache_key(self, request, view):
        return self.cache_format % {
            'scope': self.scope,
            'ident': self.get_ident(request)
        }