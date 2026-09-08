import logging
from time import monotonic

from authentication.utils import log_action

logger = logging.getLogger(__name__)


class ActionAuditMiddleware:
    """One request record, in addition to the existing domain activity entries."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        started = monotonic()
        response = self.get_response(request)
        if not request.path.startswith('/api/') or request.method == 'OPTIONS':
            return response
        # DRF assigns its authenticated user to the underlying Django request.
        user = getattr(request, 'user', None)
        if not getattr(user, 'is_authenticated', False):
            user = None
        match = request.resolver_match
        # Store the route template, never query strings or user-provided paths.
        route = str(match.route)[:250] if match else 'unmatched'
        try:
            log_action(request, 'api.request', user=user, metadata={
                'method': request.method,
                'route': route,
                'status_code': response.status_code,
                'duration_ms': round((monotonic() - started) * 1000),
            })
        except Exception:
            # Logging must not turn an already-committed mutation into a 500.
            logger.exception('Could not persist API action audit')
        return response
