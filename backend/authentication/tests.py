from unittest.mock import patch

from django.test import override_settings
from rest_framework.test import APITestCase
from rest_framework import status

from profiles.models import Profile


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
