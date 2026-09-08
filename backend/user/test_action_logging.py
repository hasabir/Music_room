from unittest.mock import patch

from django.core.cache import cache
from django.test import override_settings
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from user.models import ActionLog, User


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class ActionLoggingTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(email='audit@example.com', password='test-pass')
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Bearer {AccessToken.for_user(self.user)}',
            HTTP_X_PLATFORM='Android', HTTP_X_DEVICE='Samsung SM-S911B',
            HTTP_X_APP_VERSION='1.0.0+1',
        )

    def test_read_is_logged_with_jwt_user_and_device_metadata(self):
        response = self.client.get('/api/v1/user/me/?token=never-log-this')
        self.assertEqual(response.status_code, 200)
        entry = ActionLog.objects.get(action='api.request')
        self.assertEqual(entry.user, self.user)
        self.assertEqual((entry.platform, entry.device, entry.app_version),
                         ('Android', 'Samsung SM-S911B', '1.0.0+1'))
        self.assertEqual(entry.metadata['status_code'], 200)
        self.assertNotIn('never-log-this', str(entry.metadata))

    def test_failed_anonymous_request_is_logged_without_credentials(self):
        self.client.credentials(HTTP_X_PLATFORM='Web')
        response = self.client.post('/api/v1/user/subscription/',
                                    {'tier': 'premium', 'password': 'never-log-this'}, format='json')
        self.assertIn(response.status_code, (401, 403))
        entry = ActionLog.objects.get(action='api.request')
        self.assertIsNone(entry.user)
        self.assertEqual(entry.metadata['status_code'], response.status_code)
        self.assertNotIn('never-log-this', str(entry.metadata))

    def test_domain_entry_is_preserved_alongside_request_audit(self):
        response = self.client.post('/api/v1/user/subscription/', {'tier': 'premium'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(ActionLog.objects.filter(action='api.request').count(), 1)
        entry = ActionLog.objects.get(action='user.subscription_changed')
        self.assertEqual(entry.device, 'Samsung SM-S911B')

    def test_client_action_cannot_forge_another_user_or_server_action(self):
        response = self.client.post('/api/v1/user/actions/',
                                    {'action': 'playback.pause', 'user': 999}, format='json')
        self.assertEqual(response.status_code, 204)
        self.assertEqual(ActionLog.objects.get(action='client.playback.pause').user, self.user)
        response = self.client.post('/api/v1/user/actions/',
                                    {'action': 'user.subscription_changed'}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(ActionLog.objects.filter(action='user.subscription_changed').exists())

    def test_anonymous_local_action_is_supported(self):
        self.client.credentials(HTTP_X_PLATFORM='Web')
        self.assertEqual(self.client.post('/api/v1/user/actions/',
                                         {'action': 'navigation'}, format='json').status_code, 204)
        self.assertIsNone(ActionLog.objects.get(action='client.navigation').user)

    def test_oversized_headers_and_invalid_ip_do_not_break_actions(self):
        self.client.credentials(HTTP_X_DEVICE='x' * 1000, HTTP_X_FORWARDED_FOR='invalid')
        response = self.client.post('/api/v1/user/actions/', {'action': 'interaction'}, format='json')
        self.assertEqual(response.status_code, 204)
        entry = ActionLog.objects.get(action='client.interaction')
        self.assertEqual(len(entry.device), 100)
        self.assertIsNone(entry.ip_address)

    def test_preflight_allows_metadata_headers_and_does_not_create_log(self):
        response = self.client.options('/api/v1/user/actions/',
            HTTP_ORIGIN='http://localhost:5000', HTTP_ACCESS_CONTROL_REQUEST_METHOD='POST',
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS='x-platform,x-device,x-app-version')
        self.assertEqual(response.status_code, 200)
        for header in ('x-platform', 'x-device', 'x-app-version'):
            self.assertIn(header, response['Access-Control-Allow-Headers'])
        self.assertFalse(ActionLog.objects.exists())

    def test_unknown_route_does_not_store_user_controlled_path(self):
        self.assertEqual(self.client.get('/api/secret-value/').status_code, 404)
        self.assertEqual(ActionLog.objects.get().metadata['route'], 'unmatched')

    @patch('user.middleware.log_action', side_effect=RuntimeError('storage unavailable'))
    def test_audit_failure_does_not_change_api_response(self, _mock):
        with self.assertLogs('user.middleware', level='ERROR'):
            response = self.client.get('/api/v1/user/me/')
        self.assertEqual(response.status_code, 200)

    def test_client_action_endpoint_is_rate_limited(self):
        with patch('user.views.ClientActionThrottle.rate', '1/min'):
            self.assertEqual(self.client.post('/api/v1/user/actions/',
                {'action': 'interaction'}, format='json').status_code, 204)
            self.assertEqual(self.client.post('/api/v1/user/actions/',
                {'action': 'interaction'}, format='json').status_code, 429)
