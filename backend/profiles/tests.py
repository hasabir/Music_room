from django.test import override_settings
from rest_framework.test import APITestCase
from rest_framework import status

from user.models import User
from .models import AVATAR_PRESET_IDS, Profile
from .services import create_profile_for_user


def create_verified_user(email, password="TestPass123"):
    user = User.objects.create_user(email=email, password=password, registration_method="email")
    user.is_email_verified = True
    user.save(update_fields=["is_email_verified"])
    return user


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class AvatarAssignmentTests(APITestCase):
    """`create_profile_for_user` is the one place both the email-verification
    and Google-sign-in flows create a profile through — see
    `authentication.views.VerifyEmailView` / `GoogleLoginView`."""

    def test_new_profile_gets_a_random_preset_by_default(self):
        user = create_verified_user("host@test.com")
        profile = create_profile_for_user(user)

        self.assertEqual(profile.avatar_type, "preset")
        self.assertIn(profile.avatar_preset_id, AVATAR_PRESET_IDS)
        self.assertEqual(profile.avatar_external_url, "")

    def test_new_profile_uses_a_given_external_url_instead_of_a_preset(self):
        user = create_verified_user("google-user@test.com")
        profile = create_profile_for_user(
            user, avatar_external_url="https://lh3.googleusercontent.com/a/photo.jpg"
        )

        self.assertEqual(profile.avatar_type, "external_url")
        self.assertEqual(
            profile.avatar_external_url, "https://lh3.googleusercontent.com/a/photo.jpg"
        )

    def test_existing_profile_is_not_overwritten_by_a_later_external_url(self):
        user = create_verified_user("returning@test.com")
        first = create_profile_for_user(user)
        original_preset = first.avatar_preset_id

        second = create_profile_for_user(user, avatar_external_url="https://example.test/x.jpg")

        second.refresh_from_db()
        self.assertEqual(second.avatar_type, "preset")
        self.assertEqual(second.avatar_preset_id, original_preset)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class ProfileAvatarApiTests(APITestCase):

    def setUp(self):
        self.user = create_verified_user("host@test.com")
        self.client.force_authenticate(self.user)
        self.profile = create_profile_for_user(self.user)

    def test_my_profile_response_includes_unified_avatar_fields(self):
        response = self.client.get("/api/v1/profile/me/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["avatar_type"], "preset")
        self.assertEqual(response.data["avatar"], self.profile.avatar_preset_id)

    def test_picking_a_preset_updates_avatar_type_and_avatar(self):
        current = self.profile.avatar_preset_id
        new_preset = next(pid for pid in AVATAR_PRESET_IDS if pid != current)

        response = self.client.patch(
            "/api/v1/profile/me/", {"avatar_preset_id": new_preset}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["avatar_type"], "preset")
        self.assertEqual(response.data["avatar_preset_id"], new_preset)
        self.assertEqual(response.data["avatar"], new_preset)

    def test_rejects_an_unknown_preset_id(self):
        response = self.client.patch(
            "/api/v1/profile/me/", {"avatar_preset_id": "not-a-real-preset"}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_client_cannot_set_avatar_type_directly(self):
        response = self.client.patch(
            "/api/v1/profile/me/",
            {"avatar_type": "external_url", "avatar_external_url": "https://evil.test/x.jpg"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.profile.refresh_from_db()
        # Silently ignored (read-only field) — avatar_type is still
        # whatever it already was, not attacker-controlled.
        self.assertEqual(self.profile.avatar_type, "preset")

    def test_uploading_a_custom_image_switches_avatar_type_and_clears_preset(self):
        from django.core.files.uploadedfile import SimpleUploadedFile

        # Minimal valid 1x1 GIF — Django's ImageField validates actual
        # image content (via Pillow), so arbitrary bytes get rejected.
        gif_1px = (
            b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04"
            b"\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;"
        )
        image = SimpleUploadedFile("avatar.gif", gif_1px, content_type="image/gif")
        response = self.client.patch(
            "/api/v1/profile/me/", {"profile_image": image}, format="multipart"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["avatar_type"], "custom")
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.avatar_preset_id, "")
        self.assertTrue(self.profile.avatar_type == "custom")

    def test_avatar_is_always_visible_on_another_users_profile(self):
        other = create_verified_user("stranger@test.com")
        other_profile = create_profile_for_user(other)

        response = self.client.get(f"/api/v1/profile/profile/{other.id}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["avatar_type"], "preset")
        self.assertEqual(response.data["avatar"], other_profile.avatar_preset_id)
