from unittest.mock import patch

from django.test import override_settings
from rest_framework.test import APITestCase
from rest_framework import status

from profiles.models import Profile
from user.models import User, SocialAccount


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class GoogleLoginAvatarTests(APITestCase):
    """A new account created via Google sign-in seeds its avatar from the
    Google account's photo when one is present, falling back to the same
    random-preset assignment as any other new account otherwise — see
    `GoogleLoginView` / `profiles.services.create_profile_for_user` /
    DECISIONS.md."""

    def _idinfo(self, **overrides):
        return {
            "sub": "google-uid-123",
            "email": "newuser@test.com",
            "email_verified": True,
            "given_name": "New",
            "family_name": "User",
            **overrides,
        }

    @patch("google.oauth2.id_token.verify_oauth2_token")
    def test_google_photo_becomes_the_new_accounts_avatar(self, mock_verify):
        mock_verify.return_value = self._idinfo(
            picture="https://lh3.googleusercontent.com/a/photo.jpg"
        )

        response = self.client.post(
            "/api/v1/auth/google/", {"id_token": "fake-token"}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        profile = Profile.objects.get(user__email="newuser@test.com")
        self.assertEqual(profile.avatar_type, "external_url")
        self.assertEqual(
            profile.avatar_external_url, "https://lh3.googleusercontent.com/a/photo.jpg"
        )

    @patch("google.oauth2.id_token.verify_oauth2_token")
    def test_missing_google_photo_falls_back_to_a_random_preset(self, mock_verify):
        mock_verify.return_value = self._idinfo(picture="")

        response = self.client.post(
            "/api/v1/auth/google/", {"id_token": "fake-token"}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        profile = Profile.objects.get(user__email="newuser@test.com")
        self.assertEqual(profile.avatar_type, "preset")
        self.assertNotEqual(profile.avatar_preset_id, "")


def _idinfo(**overrides):
    return {
        "sub": "google-uid-123",
        "email": "google@test.com",
        "email_verified": True,
        "given_name": "Google",
        "family_name": "User",
        **overrides,
    }


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class GoogleLinkTests(APITestCase):
    """`GoogleLinkView.post` — see DECISIONS.md for why linking never
    requires the Google email to match the platform email, and why a
    second Google account is rejected rather than replacing the first."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="user@test.com", password="TestPass123", registration_method="email"
        )
        self.user.is_email_verified = True
        self.user.save(update_fields=["is_email_verified"])
        self.url = "/api/v1/auth/google/link/"

    @patch("google.oauth2.id_token.verify_oauth2_token")
    def test_link_succeeds_even_when_google_email_differs_from_account_email(self, mock_verify):
        mock_verify.return_value = _idinfo(email="totally-different@gmail.com")
        self.client.force_authenticate(self.user)

        response = self.client.post(self.url, {"id_token": "fake"}, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        social_account = SocialAccount.objects.get(user=self.user)
        self.assertEqual(social_account.provider_uid, "google-uid-123")
        self.assertEqual(social_account.email, "totally-different@gmail.com")
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "user@test.com")  # never overwritten

    def test_link_requires_authentication(self):
        response = self.client.post(self.url, {"id_token": "fake"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    @patch("google.oauth2.id_token.verify_oauth2_token")
    def test_relinking_the_same_google_account_is_idempotent(self, mock_verify):
        mock_verify.return_value = _idinfo()
        self.client.force_authenticate(self.user)

        first = self.client.post(self.url, {"id_token": "fake"}, format="json")
        second = self.client.post(self.url, {"id_token": "fake"}, format="json")

        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertEqual(SocialAccount.objects.filter(user=self.user).count(), 1)

    @patch("google.oauth2.id_token.verify_oauth2_token")
    def test_link_rejects_google_account_already_linked_to_a_different_user(self, mock_verify):
        other_user = User.objects.create_user(
            email="other@test.com", password="TestPass123", registration_method="email"
        )
        SocialAccount.objects.create(
            user=other_user, provider_uid="google-uid-123", email="google@test.com"
        )

        mock_verify.return_value = _idinfo()
        self.client.force_authenticate(self.user)

        response = self.client.post(self.url, {"id_token": "fake"}, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(SocialAccount.objects.filter(user=self.user).exists())

    @patch("google.oauth2.id_token.verify_oauth2_token")
    def test_link_rejects_a_second_google_account_when_one_is_already_linked(self, mock_verify):
        SocialAccount.objects.create(
            user=self.user, provider_uid="existing-uid", email="existing@gmail.com"
        )

        mock_verify.return_value = _idinfo(sub="a-different-uid")
        self.client.force_authenticate(self.user)

        response = self.client.post(self.url, {"id_token": "fake"}, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(SocialAccount.objects.filter(user=self.user).count(), 1)
        self.assertTrue(
            SocialAccount.objects.filter(user=self.user, provider_uid="existing-uid").exists()
        )

    @patch("google.oauth2.id_token.verify_oauth2_token", side_effect=ValueError("Wrong number of segments"))
    def test_link_rejects_invalid_token(self, mock_verify):
        self.client.force_authenticate(self.user)

        response = self.client.post(self.url, {"id_token": "garbage"}, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(SocialAccount.objects.filter(user=self.user).exists())


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class GoogleUnlinkTests(APITestCase):
    """`GoogleLinkView.delete` — see DECISIONS.md for why the guard is
    `has_usable_password()` rather than `registration_method == "email"`."""

    def setUp(self):
        self.url = "/api/v1/auth/google/link/"

    def test_unlink_succeeds_for_an_email_password_user(self):
        user = User.objects.create_user(
            email="user@test.com", password="TestPass123", registration_method="email"
        )
        SocialAccount.objects.create(user=user, provider_uid="google-uid-123", email="google@test.com")
        self.client.force_authenticate(user)

        response = self.client.delete(self.url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(SocialAccount.objects.filter(user=user).exists())

    def test_unlink_rejects_when_nothing_is_linked(self):
        user = User.objects.create_user(
            email="user@test.com", password="TestPass123", registration_method="email"
        )
        self.client.force_authenticate(user)

        response = self.client.delete(self.url)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_unlink_blocked_for_a_google_only_signup_with_no_usable_password(self):
        user = User.objects.create_user(
            email="googleuser@test.com", registration_method="google"
        )  # no password given -> set_unusable_password()
        SocialAccount.objects.create(
            user=user, provider_uid="google-uid-123", email="googleuser@test.com"
        )
        self.client.force_authenticate(user)

        response = self.client.delete(self.url)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(SocialAccount.objects.filter(user=user).exists())

    def test_unlink_requires_authentication(self):
        response = self.client.delete(self.url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class RegisterPasswordValidationTests(APITestCase):
    """RegisterSerializer.validate_password enforces AUTH_PASSWORD_VALIDATORS
    (config/settings.py) — previously only `min_length=8` was checked here,
    unlike ChangePasswordSerializer/PasswordResetNewPasswordSerializer,
    which already ran the full validator chain."""

    url = "/api/v1/auth/register/"

    def _payload(self, **overrides):
        return {
            "email": "newuser@test.com",
            "password": "correct horse battery staple",
            "first_name": "New",
            "last_name": "User",
            **overrides,
        }

    def test_registration_succeeds_with_a_strong_password(self):
        response = self.client.post(self.url, self._payload(), format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.filter(email="newuser@test.com").exists())

    def test_rejects_an_all_numeric_password(self):
        response = self.client.post(
            self.url, self._payload(password="19283746"), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", response.data)
        self.assertFalse(User.objects.filter(email="newuser@test.com").exists())

    def test_rejects_a_common_password(self):
        response = self.client.post(
            self.url, self._payload(password="password123"), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", response.data)
        self.assertFalse(User.objects.filter(email="newuser@test.com").exists())

    def test_still_rejects_a_too_short_password(self):
        response = self.client.post(
            self.url, self._payload(password="Sh0rt!"), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", response.data)


class LoginUnverifiedEmailTests(APITestCase):
    """LoginView rejects an unverified email/password account with a bare
    string `code` (not list-wrapped) — see EmailNotVerifiedError's doc
    comment. A raised serializers.ValidationError would have DRF wrap
    `code` as `["email_not_verified"]`, which the mobile client's
    `error.code == 'email_not_verified'` check can't match."""

    url = "/api/v1/auth/login/"

    def setUp(self):
        self.user = User.objects.create_user(
            email="unverified@test.com", password="TestPass123", registration_method="email"
        )

    def test_login_rejected_with_a_bare_string_code(self):
        response = self.client.post(
            self.url, {"email": "unverified@test.com", "password": "TestPass123"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["code"], "email_not_verified")
        self.assertIsInstance(response.data["detail"], str)

    def test_verified_account_logs_in_normally(self):
        self.user.is_email_verified = True
        self.user.save(update_fields=["is_email_verified"])

        response = self.client.post(
            self.url, {"email": "unverified@test.com", "password": "TestPass123"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
