from django.test import override_settings
from rest_framework.test import APITestCase
from rest_framework import status

from user.models import User
from events.models import Event, EventLike
from .models import AVATAR_PRESET_IDS, Friendship, Profile
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


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class FavoriteGenresVisibilityTests(APITestCase):
    """`favorite_genres` ("Vibe Signature" on the client) used to be
    unconditionally visible on another user's profile, same bucket as
    avatar/display_name. It now respects `field_visibility` like bio/
    location/favorite_artist/phone_number/birthday already did — see
    `UserProfileView`. Defaults to 'public' so a profile that hasn't
    picked a tier for it keeps its previous always-visible behavior."""

    def setUp(self):
        self.owner = create_verified_user("owner@test.com")
        self.owner_profile = create_profile_for_user(self.owner)
        self.owner_profile.favorite_genres = ["jazz", "soul"]
        self.owner_profile.save(update_fields=["favorite_genres"])

        self.friend = create_verified_user("friend@test.com")
        create_profile_for_user(self.friend)
        Friendship.objects.create(sender=self.owner, receiver=self.friend, status="accepted")

        self.stranger = create_verified_user("stranger@test.com")
        create_profile_for_user(self.stranger)

        self.profile_url = f"/api/v1/profile/profile/{self.owner.id}/"

    def test_defaults_to_visible_for_a_stranger(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.profile_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["favorite_genres"], ["jazz", "soul"])

    def test_hidden_from_a_stranger_once_set_to_friends_only(self):
        self.owner_profile.field_visibility["favorite_genres"] = "friends"
        self.owner_profile.save(update_fields=["field_visibility"])

        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.profile_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertNotIn("favorite_genres", response.data)

    def test_visible_to_a_friend_when_set_to_friends_only(self):
        self.owner_profile.field_visibility["favorite_genres"] = "friends"
        self.owner_profile.save(update_fields=["field_visibility"])

        self.client.force_authenticate(self.friend)
        response = self.client.get(self.profile_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["favorite_genres"], ["jazz", "soul"])

    def test_hidden_from_everyone_including_friends_when_private(self):
        self.owner_profile.field_visibility["favorite_genres"] = "private"
        self.owner_profile.save(update_fields=["field_visibility"])

        self.client.force_authenticate(self.friend)
        response = self.client.get(self.profile_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertNotIn("favorite_genres", response.data)

    def test_always_visible_to_the_owner_themselves(self):
        self.owner_profile.field_visibility["favorite_genres"] = "private"
        self.owner_profile.save(update_fields=["field_visibility"])

        self.client.force_authenticate(self.owner)
        response = self.client.get(self.profile_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["favorite_genres"], ["jazz", "soul"])

    def test_owner_can_set_the_tier_via_patch(self):
        self.client.force_authenticate(self.owner)
        response = self.client.patch(
            "/api/v1/profile/me/",
            {"field_visibility": {"favorite_genres": "private"}},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["field_visibility"]["favorite_genres"], "private")


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class LikesReceivedCountTests(APITestCase):
    """
    ProfileSerializer.likes_received_count — total likes across every
    event the profile's user *hosts*, not likes they've given elsewhere.
    Replaces the old votes_count field (see todo.todo).
    """

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.other_user = create_verified_user("other@test.com")
        self.client.force_authenticate(self.host)

    def test_defaults_to_zero_with_no_events(self):
        response = self.client.get("/api/v1/profile/me/")
        self.assertEqual(response.data["likes_received_count"], 0)

    def test_counts_likes_across_all_hosted_events(self):
        event_a = Event.objects.create(host=self.host, title="Party A")
        event_b = Event.objects.create(host=self.host, title="Party B")
        liker_one = create_verified_user("liker1@test.com")
        liker_two = create_verified_user("liker2@test.com")
        EventLike.objects.create(event=event_a, user=liker_one)
        EventLike.objects.create(event=event_a, user=liker_two)
        EventLike.objects.create(event=event_b, user=liker_one)

        response = self.client.get("/api/v1/profile/me/")
        self.assertEqual(response.data["likes_received_count"], 3)

    def test_does_not_count_likes_the_user_gave_on_someone_elses_event(self):
        others_event = Event.objects.create(host=self.other_user, title="Not Mine")
        EventLike.objects.create(event=others_event, user=self.host)

        response = self.client.get("/api/v1/profile/me/")
        self.assertEqual(response.data["likes_received_count"], 0)

    def test_visible_on_another_user_s_public_profile(self):
        event = Event.objects.create(host=self.host, title="Party")
        EventLike.objects.create(event=event, user=self.other_user)

        self.client.force_authenticate(self.other_user)
        response = self.client.get(f"/api/v1/profile/profile/{self.host.id}/")
        self.assertEqual(response.data["likes_received_count"], 1)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class UserProfileRelationshipFieldTests(APITestCase):
    """
    UserProfileView (GET /profile/profile/<user_id>/) — the `username`,
    `relationship_status`, and `friendship_id` fields added alongside
    `likes_received_count`/`playlists_count`, so a viewer can render a
    friend-request action without a separate lookup. Mirrors the same
    states `UserSearchView` already reports, computed here via the shared
    `profiles.services.relationship_status` helper.
    """

    def setUp(self):
        self.viewer = create_verified_user("viewer@test.com")
        self.target = create_verified_user("target@test.com")
        self.client.force_authenticate(self.viewer)

    def _profile_url(self, user):
        return f"/api/v1/profile/profile/{user.id}/"

    def test_username_is_always_returned(self):
        response = self.client.get(self._profile_url(self.target))
        self.assertEqual(response.data["username"], self.target.username)

    def test_relationship_status_defaults_to_none(self):
        response = self.client.get(self._profile_url(self.target))
        self.assertEqual(response.data["relationship_status"], "none")
        self.assertIsNone(response.data["friendship_id"])

    def test_relationship_status_reflects_a_pending_sent_request(self):
        friendship = Friendship.objects.create(sender=self.viewer, receiver=self.target, status="pending")
        response = self.client.get(self._profile_url(self.target))
        self.assertEqual(response.data["relationship_status"], "pending_sent")
        self.assertEqual(response.data["friendship_id"], friendship.id)

    def test_relationship_status_reflects_a_pending_received_request(self):
        friendship = Friendship.objects.create(sender=self.target, receiver=self.viewer, status="pending")
        response = self.client.get(self._profile_url(self.target))
        self.assertEqual(response.data["relationship_status"], "pending_received")
        self.assertEqual(response.data["friendship_id"], friendship.id)

    def test_relationship_status_reflects_accepted_friends(self):
        friendship = Friendship.objects.create(sender=self.viewer, receiver=self.target, status="accepted")
        response = self.client.get(self._profile_url(self.target))
        self.assertEqual(response.data["relationship_status"], "friends")
        self.assertEqual(response.data["friendship_id"], friendship.id)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class SearchAndFriendAvatarFieldTests(APITestCase):
    """
    UserSearchView and FriendSerializer (used by FriendListView, and
    nested in FriendshipSerializer for the received/sent requests lists)
    expose avatar/avatar_type — same pattern used everywhere else a
    user's avatar is shown (see events.tests.ParticipantAvatarFieldTests,
    playlists.tests.PlaylistParticipantAvatarFieldTests).
    """

    def setUp(self):
        self.viewer = create_verified_user("viewer@test.com")
        self.other = create_verified_user("other_person@test.com")
        self.client.force_authenticate(self.viewer)

    def test_search_result_avatar_defaults_when_no_profile(self):
        response = self.client.get("/api/v1/profile/search/?q=other_person")
        result = next(r for r in response.data if r["id"] == self.other.id)
        self.assertIsNone(result["avatar"])
        self.assertEqual(result["avatar_type"], "preset")

    def test_search_result_avatar_reflects_their_profile(self):
        from profiles.services import create_profile_for_user

        profile = create_profile_for_user(self.other)
        profile.avatar_preset_id = "7"
        profile.save(update_fields=["avatar_preset_id"])

        response = self.client.get("/api/v1/profile/search/?q=other_person")
        result = next(r for r in response.data if r["id"] == self.other.id)
        self.assertEqual(result["avatar"], "7")
        self.assertEqual(result["avatar_type"], "preset")

    def test_friend_list_includes_avatar_and_username(self):
        from profiles.services import create_profile_for_user

        profile = create_profile_for_user(self.other)
        profile.avatar_preset_id = "2"
        profile.save(update_fields=["avatar_preset_id"])
        Friendship.objects.create(sender=self.viewer, receiver=self.other, status="accepted")

        response = self.client.get("/api/v1/profile/friends/")
        friend = response.data["results"][0]
        self.assertEqual(friend["avatar"], "2")
        self.assertEqual(friend["username"], self.other.username)
