from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from user.models import Notification, User
from user.notifications import notify_user


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SubscriptionSwitchTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='sub@example.com', password='test-pass')
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Bearer {AccessToken.for_user(self.user)}',
        )

    def test_upgrading_to_premium_sets_an_expiry_about_30_days_out(self):
        response = self.client.post('/api/v1/user/subscription/', {'tier': 'premium'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertIsNotNone(self.user.subscription_expires_at)
        delta = self.user.subscription_expires_at - timezone.now()
        self.assertTrue(29 <= delta.days <= 30)
        self.assertIsNotNone(response.data['user']['subscription_expires_at'])

    def test_downgrading_to_free_clears_the_expiry(self):
        self.client.post('/api/v1/user/subscription/', {'tier': 'premium'}, format='json')
        response = self.client.post('/api/v1/user/subscription/', {'tier': 'free'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertIsNone(self.user.subscription_expires_at)
        self.assertIsNone(response.data['user']['subscription_expires_at'])


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class NotificationTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='notif@example.com', password='test-pass')
        self.other_user = User.objects.create_user(email='other@example.com', password='test-pass')
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Bearer {AccessToken.for_user(self.user)}',
        )

    def test_notify_user_persists_a_row_the_recipient_can_list(self):
        notify_user(
            self.user.id, kind='playlist_invite', title='Playlist invitation',
            body='You were invited.', data={'playlist_id': 7},
        )
        response = self.client.get('/api/v1/user/notifications/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        entry = response.data[0]
        self.assertEqual(entry['kind'], 'playlist_invite')
        self.assertEqual(entry['data'], {'playlist_id': 7})
        self.assertFalse(entry['is_read'])

    def test_list_only_returns_the_signed_in_users_own_notifications(self):
        notify_user(self.user.id, kind='friend_request', title='t', body='b')
        notify_user(self.other_user.id, kind='friend_request', title='t', body='b')
        response = self.client.get('/api/v1/user/notifications/')
        self.assertEqual(len(response.data), 1)

    def test_marking_one_notification_read(self):
        notification = Notification.objects.create(
            user=self.user, kind='friend_request', title='t', body='b',
        )
        response = self.client.post(f'/api/v1/user/notifications/{notification.id}/read/')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['is_read'])
        notification.refresh_from_db()
        self.assertTrue(notification.is_read)

    def test_cannot_mark_another_users_notification_read(self):
        notification = Notification.objects.create(
            user=self.other_user, kind='friend_request', title='t', body='b',
        )
        response = self.client.post(f'/api/v1/user/notifications/{notification.id}/read/')
        self.assertEqual(response.status_code, 404)

    def test_mark_all_read(self):
        Notification.objects.create(user=self.user, kind='friend_request', title='t', body='b')
        Notification.objects.create(user=self.user, kind='event_invite', title='t', body='b')
        response = self.client.post('/api/v1/user/notifications/read-all/')
        self.assertEqual(response.status_code, 204)
        self.assertEqual(Notification.objects.filter(user=self.user, is_read=False).count(), 0)
