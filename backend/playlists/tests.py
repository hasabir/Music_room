# playlists/tests.py
from django.test import override_settings
from rest_framework.test import APITestCase
from rest_framework import status

from user.models import User
from events.models import Song
from .models import Playlist, PlaylistSong, PlaylistCollaborator


def create_verified_user(email, password="TestPass123"):
    user = User.objects.create_user(email=email, password=password, registration_method="email")
    user.is_email_verified = True
    user.save(update_fields=["is_email_verified"])
    return user


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class PlaylistTests(APITestCase):

    def setUp(self):
        self.owner = create_verified_user("owner@test.com")
        self.other_user = create_verified_user("other@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.playlists_url = "/api/v1/playlists/"

    def test_create_playlist_defaults(self):
        self.client.force_authenticate(self.owner)
        response = self.client.post(self.playlists_url, {"title": "Road Trip"})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["visibility"], "public")
        self.assertEqual(response.data["edit_permission"], "everyone")
        self.assertEqual(response.data["song_count"], 0)

    def test_private_playlist_not_visible_to_stranger(self):
        self.client.force_authenticate(self.owner)
        create_resp = self.client.post(self.playlists_url, {"title": "Secret Mix", "visibility": "private"})
        playlist_id = create_resp.data["id"]

        self.client.force_authenticate(self.stranger)
        response = self.client.get(f"{self.playlists_url}{playlist_id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_only_owner_can_update_playlist(self):
        self.client.force_authenticate(self.owner)
        create_resp = self.client.post(self.playlists_url, {"title": "Mix"})
        playlist_id = create_resp.data["id"]

        self.client.force_authenticate(self.other_user)
        response = self.client.patch(f"{self.playlists_url}{playlist_id}/", {"title": "Hijacked"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_only_owner_can_delete_playlist(self):
        self.client.force_authenticate(self.owner)
        create_resp = self.client.post(self.playlists_url, {"title": "Mix"})
        playlist_id = create_resp.data["id"]

        self.client.force_authenticate(self.other_user)
        response = self.client.delete(f"{self.playlists_url}{playlist_id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class PlaylistSongTests(APITestCase):

    def setUp(self):
        self.owner = create_verified_user("owner@test.com")
        self.editor = create_verified_user("editor@test.com")
        # This class tests add/remove/move mechanics on a public playlist
        # (edit_permission, position bookkeeping) — none of that is what
        # PlaylistPremiumGateTests below already covers dedicatedly, so
        # make the owner Premium here to keep testing only what this
        # class has always tested, unaffected by the new gate.
        self.owner.subscription_tier = User.SUBSCRIPTION_PREMIUM
        self.owner.save(update_fields=["subscription_tier"])

        self.client.force_authenticate(self.owner)
        playlist_resp = self.client.post("/api/v1/playlists/", {"title": "Test Playlist"})
        self.playlist_id = playlist_resp.data["id"]
        self.songs_url = f"/api/v1/playlists/{self.playlist_id}/songs/"

    def _add_song(self, title, artist):
        return self.client.post(self.songs_url, {"title": title, "artist": artist})

    def _move_song(self, playlist_song_id, new_position):
        return self.client.post(f"{self.songs_url}{playlist_song_id}/move/", {"new_position": new_position})

    # ---------- ADD ----------

    def test_add_song_goes_to_end(self):
        self._add_song("Song A", "Artist A")
        response = self._add_song("Song B", "Artist B")
        self.assertEqual(response.data["position"], 1)

    def test_adding_same_song_twice_fails(self):
        self._add_song("Song A", "Artist A")
        response = self._add_song("Song A", "Artist A")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_add_song_reuses_existing_catalog_song(self):
        self._add_song("Song A", "Artist A")
        song_count_after_first = Song.objects.count()

        # Add the same song to a DIFFERENT playlist — should reuse the catalog Song row
        playlist2_resp = self.client.post("/api/v1/playlists/", {"title": "Second Playlist"})
        self.client.post(f"/api/v1/playlists/{playlist2_resp.data['id']}/songs/",
                          {"title": "Song A", "artist": "Artist A"})

        self.assertEqual(Song.objects.count(), song_count_after_first)  # no duplicate Song created

    def test_add_song_requires_edit_permission(self):
        self.client.force_authenticate(self.owner)
        private_resp = self.client.post("/api/v1/playlists/", {
            "title": "Invite Only", "edit_permission": "invited_only"
        })
        private_songs_url = f"/api/v1/playlists/{private_resp.data['id']}/songs/"

        self.client.force_authenticate(self.editor)
        response = self.client.post(private_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    # ---------- REMOVE (gapless positions) ----------

    def test_remove_song_shifts_later_positions_down(self):
        add_a = self._add_song("Song A", "Artist A")  # position 0
        self._add_song("Song B", "Artist B")            # position 1
        add_c = self._add_song("Song C", "Artist C")    # position 2

        # Remove the middle one
        delete_resp = self.client.delete(f"{self.songs_url}{self._get_id(add_a)}/")
        self.assertEqual(delete_resp.status_code, status.HTTP_204_NO_CONTENT)

        response = self.client.get(self.songs_url)
        positions = [s["position"] for s in response.data]
        self.assertEqual(positions, [0, 1])  # no gap, B and C shifted down

    def test_remove_nonexistent_song_fails(self):
        response = self.client.delete(f"{self.songs_url}99999/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def _get_id(self, response):
        return response.data["id"]

    # ---------- MOVE / REORDER ----------

    def test_move_song_to_front(self):
        self._add_song("Song A", "Artist A")  # position 0
        self._add_song("Song B", "Artist B")  # position 1
        add_c = self._add_song("Song C", "Artist C")  # position 2

        response = self._move_song(add_c.data["id"], 0)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["position"], 0)

        # Confirm the whole order is correct and gapless
        list_response = self.client.get(self.songs_url)
        titles_in_order = [s["song_title"] for s in list_response.data]
        self.assertEqual(titles_in_order, ["Song C", "Song A", "Song B"])

    def test_move_song_to_end(self):
        add_a = self._add_song("Song A", "Artist A")  # position 0
        self._add_song("Song B", "Artist B")            # position 1
        self._add_song("Song C", "Artist C")             # position 2

        response = self._move_song(add_a.data["id"], 2)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        list_response = self.client.get(self.songs_url)
        titles_in_order = [s["song_title"] for s in list_response.data]
        self.assertEqual(titles_in_order, ["Song B", "Song C", "Song A"])

    def test_move_song_position_out_of_range_gets_clamped(self):
        self._add_song("Song A", "Artist A")
        add_b = self._add_song("Song B", "Artist B")

        response = self._move_song(add_b.data["id"], 999)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["position"], 1)  # clamped to max valid position

    def test_positions_stay_unique_after_multiple_moves(self):
        add_a = self._add_song("Song A", "Artist A")
        add_b = self._add_song("Song B", "Artist B")
        add_c = self._add_song("Song C", "Artist C")
        add_d = self._add_song("Song D", "Artist D")

        self._move_song(add_d.data["id"], 0)
        self._move_song(add_a.data["id"], 3)
        self._move_song(add_c.data["id"], 1)

        response = self.client.get(self.songs_url)
        positions = sorted(s["position"] for s in response.data)
        self.assertEqual(positions, [0, 1, 2, 3])  # still gapless, no duplicates

    def test_move_requires_edit_permission(self):
        add_a = self._add_song("Song A", "Artist A")
        self._add_song("Song B", "Artist B")

        self.client.force_authenticate(self.owner)
        private_resp = self.client.post("/api/v1/playlists/", {
            "title": "Invite Only", "edit_permission": "invited_only"
        })
        priv_songs_url = f"/api/v1/playlists/{private_resp.data['id']}/songs/"
        self.client.post(priv_songs_url, {"title": "X", "artist": "Y"})
        add_priv_b = self.client.post(priv_songs_url, {"title": "Z", "artist": "W"})

        self.client.force_authenticate(self.editor)
        response = self.client.post(
            f"{priv_songs_url}{add_priv_b.data['id']}/move/", {"new_position": 0}
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class PlaylistCollaboratorTests(APITestCase):

    def setUp(self):
        self.owner = create_verified_user("owner@test.com")
        self.collaborator = create_verified_user("collab@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.owner)
        playlist_resp = self.client.post("/api/v1/playlists/", {"title": "Private Mix", "visibility": "private"})
        self.playlist_id = playlist_resp.data["id"]
        self.collaborators_url = f"/api/v1/playlists/{self.playlist_id}/collaborators/"

    def test_owner_can_invite_collaborator(self):
        response = self.client.post(self.collaborators_url, {"user_id": self.collaborator.id})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_non_owner_cannot_invite_collaborator(self):
        self.client.force_authenticate(self.collaborator)
        response = self.client.post(self.collaborators_url, {"user_id": self.stranger.id})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_invited_collaborator_can_see_private_playlist(self):
        self.client.post(self.collaborators_url, {"user_id": self.collaborator.id})

        self.client.force_authenticate(self.collaborator)
        response = self.client.get(f"/api/v1/playlists/{self.playlist_id}/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_owner_can_remove_collaborator(self):
        self.client.post(self.collaborators_url, {"user_id": self.collaborator.id})
        response = self.client.delete(f"{self.collaborators_url}{self.collaborator.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

        self.client.force_authenticate(self.collaborator)
        response = self.client.get(f"/api/v1/playlists/{self.playlist_id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_invited_collaborator_sees_the_invite_in_their_own_list(self):
        self.client.post(self.collaborators_url, {"user_id": self.collaborator.id})

        self.client.force_authenticate(self.collaborator)
        response = self.client.get("/api/v1/playlists/collaborators/mine/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["playlist"], self.playlist_id)
        self.assertEqual(response.data[0]["playlist_title"], "Private Mix")

    def test_stranger_sees_no_invites(self):
        self.client.post(self.collaborators_url, {"user_id": self.collaborator.id})

        self.client.force_authenticate(self.stranger)
        response = self.client.get("/api/v1/playlists/collaborators/mine/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class PlaylistCollaboratorManagerPermissionTests(APITestCase):
    """A collaborator granted `can_manage_collaborators` can invite/remove
    people and decide access requests — same as the owner — but still
    can't edit anyone's permissions (that stays owner-only)."""

    def setUp(self):
        self.owner = create_verified_user("manager_owner@test.com")
        self.manager = create_verified_user("manager@test.com")
        self.plain_collaborator = create_verified_user("plain_collab@test.com")
        self.newcomer = create_verified_user("newcomer@test.com")
        self.requester = create_verified_user("requester@test.com")

        self.client.force_authenticate(self.owner)
        playlist_resp = self.client.post(
            "/api/v1/playlists/", {"title": "Team Mix", "visibility": "private"}
        )
        self.playlist_id = playlist_resp.data["id"]
        self.collaborators_url = f"/api/v1/playlists/{self.playlist_id}/collaborators/"
        self.access_requests_url = f"/api/v1/playlists/{self.playlist_id}/access-requests/"

        self.client.post(self.collaborators_url, {"user_id": self.manager.id})
        self.client.patch(f"{self.collaborators_url}{self.manager.id}/", {
            "can_add_songs": True, "can_reorder_songs": True, "can_manage_collaborators": True,
        })
        self.client.post(self.collaborators_url, {"user_id": self.plain_collaborator.id})

    def test_manager_collaborator_can_invite(self):
        self.client.force_authenticate(self.manager)
        response = self.client.post(self.collaborators_url, {"user_id": self.newcomer.id})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_manager_collaborator_can_remove(self):
        self.client.force_authenticate(self.manager)
        response = self.client.delete(f"{self.collaborators_url}{self.plain_collaborator.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

    def test_plain_collaborator_cannot_invite_or_remove(self):
        self.client.force_authenticate(self.plain_collaborator)
        self.assertEqual(
            self.client.post(self.collaborators_url, {"user_id": self.newcomer.id}).status_code,
            status.HTTP_403_FORBIDDEN,
        )
        self.assertEqual(
            self.client.delete(f"{self.collaborators_url}{self.manager.id}/").status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_manager_collaborator_can_list_and_decide_access_requests(self):
        self.client.force_authenticate(self.requester)
        request_resp = self.client.post(self.access_requests_url, {})
        request_id = request_resp.data["id"]

        self.client.force_authenticate(self.manager)
        list_response = self.client.get(self.access_requests_url)
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(list_response.data), 1)

        decide_response = self.client.post(
            f"{self.access_requests_url}{request_id}/decide/", {"approve": True}
        )
        self.assertEqual(decide_response.status_code, status.HTTP_200_OK)
        self.assertTrue(
            PlaylistCollaborator.objects.filter(
                playlist_id=self.playlist_id, collaborator=self.requester
            ).exists()
        )

    def test_plain_collaborator_cannot_list_or_decide_access_requests(self):
        self.client.force_authenticate(self.requester)
        request_resp = self.client.post(self.access_requests_url, {})
        request_id = request_resp.data["id"]

        self.client.force_authenticate(self.plain_collaborator)
        self.assertEqual(
            self.client.get(self.access_requests_url).status_code, status.HTTP_403_FORBIDDEN
        )
        self.assertEqual(
            self.client.post(
                f"{self.access_requests_url}{request_id}/decide/", {"approve": True}
            ).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_manager_collaborator_cannot_edit_permissions(self):
        self.client.force_authenticate(self.manager)
        response = self.client.patch(f"{self.collaborators_url}{self.plain_collaborator.id}/", {
            "can_add_songs": False, "can_reorder_songs": False, "can_manage_collaborators": True,
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class PlaylistIsCollaboratorFieldTests(APITestCase):
    """`is_collaborator` on PlaylistSerializer — lets the client tell a
    public playlist the user already collaborates on apart from one
    they've merely discovered. Distinct from self-serve membership
    (`is_member` — see `PlaylistJoinTests`), which never grants
    collaborator status on its own."""

    def setUp(self):
        self.owner = create_verified_user("owner@test.com")
        self.collaborator = create_verified_user("collab@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.owner)
        create_resp = self.client.post(
            "/api/v1/playlists/", {"title": "Public Mix", "visibility": "public"}
        )
        self.playlist_id = create_resp.data["id"]
        self.detail_url = f"/api/v1/playlists/{self.playlist_id}/"

        self.client.post(
            f"/api/v1/playlists/{self.playlist_id}/collaborators/",
            {"user_id": self.collaborator.id},
        )

    def test_is_collaborator_true_for_invited_collaborator(self):
        self.client.force_authenticate(self.collaborator)
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["is_collaborator"])

    def test_is_collaborator_false_for_stranger(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["is_collaborator"])

    def test_is_collaborator_false_for_owner(self):
        self.client.force_authenticate(self.owner)
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["is_collaborator"])

    def test_is_collaborator_reflected_in_list_endpoint(self):
        self.client.force_authenticate(self.collaborator)
        response = self.client.get("/api/v1/playlists/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        playlist = next(
            p for p in response.data["results"] if p["id"] == self.playlist_id
        )
        self.assertTrue(playlist["is_collaborator"])


class PlaylistJoinTests(APITestCase):
    """Self-serve join for public playlists (`PlaylistJoinView`) — mirrors
    `events.tests.EventIsMemberFieldTests`/`EventJoinView`. Joining only
    ever records `PlaylistMembership`/`is_member`; it never creates a
    `PlaylistCollaborator` and grants no edit capability on its own."""

    def setUp(self):
        self.owner = create_verified_user("join_owner@test.com")
        self.joiner = create_verified_user("join_joiner@test.com")
        self.stranger = create_verified_user("join_stranger@test.com")

        self.client.force_authenticate(self.owner)
        public_resp = self.client.post(
            "/api/v1/playlists/", {"title": "Public Mix", "visibility": "public"}
        )
        self.public_id = public_resp.data["id"]
        self.public_join_url = f"/api/v1/playlists/{self.public_id}/join/"
        self.public_detail_url = f"/api/v1/playlists/{self.public_id}/"

        private_resp = self.client.post(
            "/api/v1/playlists/", {"title": "Private Mix", "visibility": "private"}
        )
        self.private_id = private_resp.data["id"]
        self.private_join_url = f"/api/v1/playlists/{self.private_id}/join/"

    def test_join_public_playlist(self):
        self.client.force_authenticate(self.joiner)
        response = self.client.post(self.public_join_url, {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_is_member_true_after_joining(self):
        self.client.force_authenticate(self.joiner)
        self.client.post(self.public_join_url, {})
        response = self.client.get(self.public_detail_url)
        self.assertTrue(response.data["is_member"])

    def test_is_member_false_for_stranger_who_has_not_joined(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.public_detail_url)
        self.assertFalse(response.data["is_member"])

    def test_is_member_false_for_owner(self):
        self.client.force_authenticate(self.owner)
        response = self.client.get(self.public_detail_url)
        self.assertFalse(response.data["is_member"])

    def test_owner_cannot_join_own_playlist(self):
        self.client.force_authenticate(self.owner)
        response = self.client.post(self.public_join_url, {})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cannot_join_twice(self):
        self.client.force_authenticate(self.joiner)
        self.client.post(self.public_join_url, {})
        response = self.client.post(self.public_join_url, {})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cannot_self_join_private_playlist(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.post(self.private_join_url, {})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_joining_grants_no_edit_capability(self):
        # Joining is membership-only — it must not create a
        # PlaylistCollaborator or otherwise unlock add/reorder rights.
        self.client.force_authenticate(self.owner)
        self.client.patch(self.public_detail_url, {"edit_permission": "invited_only"})

        self.client.force_authenticate(self.joiner)
        self.client.post(self.public_join_url, {})
        response = self.client.get(self.public_detail_url)
        self.assertFalse(response.data["is_collaborator"])

        add_response = self.client.post(
            f"/api/v1/playlists/{self.public_id}/songs/",
            {"title": "Song", "artist": "Artist"},
        )
        self.assertEqual(add_response.status_code, status.HTTP_403_FORBIDDEN)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class PlaylistParticipantAvatarFieldTests(APITestCase):
    """
    PlaylistCollaboratorSerializer/PlaylistAccessRequestSerializer expose
    `collaborator_avatar`/`collaborator_avatar_type` and
    `requester_avatar`/`requester_avatar_type` — same pattern as events'
    guest/member avatar fields (see events.tests.ParticipantAvatarFieldTests),
    sourced from `profiles.services.avatar_for_user`, not visibility-gated.
    """

    def setUp(self):
        self.owner = create_verified_user("owner@test.com")
        self.collaborator = create_verified_user("collab@test.com")
        self.requester = create_verified_user("requester@test.com")

        self.client.force_authenticate(self.owner)
        playlist_resp = self.client.post("/api/v1/playlists/", {"title": "Private Mix", "visibility": "private"})
        self.playlist_id = playlist_resp.data["id"]
        self.collaborators_url = f"/api/v1/playlists/{self.playlist_id}/collaborators/"
        self.access_requests_url = f"/api/v1/playlists/{self.playlist_id}/access-requests/"

        self.client.post(self.collaborators_url, {"user_id": self.collaborator.id})

    def test_collaborator_avatar_defaults_when_no_profile(self):
        response = self.client.get(self.collaborators_url)
        row = response.data[0]
        self.assertIsNone(row["collaborator_avatar"])
        self.assertEqual(row["collaborator_avatar_type"], "preset")

    def test_collaborator_avatar_reflects_their_profile(self):
        from profiles.services import create_profile_for_user

        profile = create_profile_for_user(self.collaborator)
        profile.avatar_preset_id = "5"
        profile.save(update_fields=["avatar_preset_id"])

        response = self.client.get(self.collaborators_url)
        row = response.data[0]
        self.assertEqual(row["collaborator_avatar"], "5")
        self.assertEqual(row["collaborator_avatar_type"], "preset")

    def test_requester_avatar_reflects_their_profile(self):
        from profiles.services import create_profile_for_user

        profile = create_profile_for_user(self.requester)
        profile.avatar_type = "external_url"
        profile.avatar_external_url = "https://example.test/requester.jpg"
        profile.save(update_fields=["avatar_type", "avatar_external_url"])

        self.client.force_authenticate(self.requester)
        self.client.post(self.access_requests_url, {})

        self.client.force_authenticate(self.owner)
        response = self.client.get(self.access_requests_url)
        row = response.data[0]
        self.assertEqual(row["requester_avatar"], "https://example.test/requester.jpg")
        self.assertEqual(row["requester_avatar_type"], "external_url")

@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class PlaylistPremiumGateTests(APITestCase):
    """
    Bonus: Free vs. Premium subscription (see docs/SUBSCRIPTION_BONUS.md)
    — editing ANY playlist (public or private) requires Premium,
    regardless of edit_permission, with no owner exemption. A private
    playlist requires both conditions: access (owner/invite/
    edit_permission) AND Premium — access alone is not enough.
    """

    def setUp(self):
        self.owner = create_verified_user("premium_gate_owner@test.com")

        self.client.force_authenticate(self.owner)
        public_resp = self.client.post(
            "/api/v1/playlists/", {"title": "Public Mix", "edit_permission": "everyone"}
        )
        self.public_playlist_id = public_resp.data["id"]
        self.public_songs_url = f"/api/v1/playlists/{self.public_playlist_id}/songs/"

        private_resp = self.client.post(
            "/api/v1/playlists/",
            {"title": "Private Mix", "visibility": "private", "edit_permission": "everyone"},
        )
        self.private_playlist_id = private_resp.data["id"]
        self.private_songs_url = f"/api/v1/playlists/{self.private_playlist_id}/songs/"

    def test_free_owner_blocked_from_editing_own_public_playlist(self):
        # Owner, "everyone can edit" — would succeed under the pre-existing
        # edit_permission rules alone; the Premium gate overrides that.
        response = self.client.post(self.public_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["code"], "playlist_edit_requires_premium")

    def test_free_owner_blocked_from_editing_own_private_playlist(self):
        # Same owner, same Free tier, same "everyone can edit" setting —
        # only `visibility` differs. Must be blocked exactly like the
        # public case: access to your own playlist is not enough on its
        # own, Premium is still required.
        response = self.client.post(self.private_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["code"], "playlist_edit_requires_premium")

    def test_premium_owner_can_edit_own_public_playlist(self):
        self.owner.subscription_tier = User.SUBSCRIPTION_PREMIUM
        self.owner.save(update_fields=["subscription_tier"])

        add = self.client.post(self.public_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(add.status_code, status.HTTP_201_CREATED)

        move = self.client.post(
            f"{self.public_songs_url}{add.data['id']}/move/", {"new_position": 0}
        )
        self.assertEqual(move.status_code, status.HTTP_200_OK)

        remove = self.client.delete(f"{self.public_songs_url}{add.data['id']}/")
        self.assertEqual(remove.status_code, status.HTTP_204_NO_CONTENT)

    def test_premium_owner_can_edit_own_private_playlist(self):
        self.owner.subscription_tier = User.SUBSCRIPTION_PREMIUM
        self.owner.save(update_fields=["subscription_tier"])

        add = self.client.post(self.private_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(add.status_code, status.HTTP_201_CREATED)

        move = self.client.post(
            f"{self.private_songs_url}{add.data['id']}/move/", {"new_position": 0}
        )
        self.assertEqual(move.status_code, status.HTTP_200_OK)

        remove = self.client.delete(f"{self.private_songs_url}{add.data['id']}/")
        self.assertEqual(remove.status_code, status.HTTP_204_NO_CONTENT)

    def test_free_non_owner_blocked_from_editing_public_everyone_playlist(self):
        # A non-owner relying purely on edit_permission="everyone" — also
        # overridden, same as the owner, confirming there's no special
        # case for *who* is editing.
        other = create_verified_user("premium_gate_other@test.com")
        self.client.force_authenticate(other)
        response = self.client.post(self.public_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["code"], "playlist_edit_requires_premium")

    def test_free_invited_collaborator_blocked_from_editing_public_playlist(self):
        # A real invited PlaylistCollaborator (can_add_songs=True), not just
        # edit_permission="everyone" — the premium gate must still apply,
        # exactly as it does for the owner. Guards against a regression
        # where the collaborator-permission branch is reached before the
        # premium check instead of after it.
        collaborator = create_verified_user("premium_gate_collaborator@test.com")
        self.client.force_authenticate(self.owner)
        self.client.post(
            f"/api/v1/playlists/{self.public_playlist_id}/collaborators/",
            {"user_id": collaborator.id},
        )

        self.client.force_authenticate(collaborator)
        response = self.client.post(self.public_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["code"], "playlist_edit_requires_premium")

    def test_free_invited_collaborator_blocked_from_editing_private_playlist(self):
        # An invited collaborator on a PRIVATE playlist — access via
        # invite is not enough on its own; Premium is still required. This
        # is the scenario originally reported as a bug (it wasn't — private
        # playlists simply weren't gated at all at the time).
        collaborator = create_verified_user("premium_gate_private_collaborator@test.com")
        self.client.force_authenticate(self.owner)
        self.client.post(
            f"/api/v1/playlists/{self.private_playlist_id}/collaborators/",
            {"user_id": collaborator.id},
        )

        self.client.force_authenticate(collaborator)
        response = self.client.post(self.private_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["code"], "playlist_edit_requires_premium")

    def test_premium_invited_collaborator_can_edit_private_playlist(self):
        # Both conditions met — invited AND Premium — succeeds.
        collaborator = create_verified_user("premium_gate_premium_private_collaborator@test.com")
        collaborator.subscription_tier = User.SUBSCRIPTION_PREMIUM
        collaborator.save(update_fields=["subscription_tier"])

        self.client.force_authenticate(self.owner)
        self.client.post(
            f"/api/v1/playlists/{self.private_playlist_id}/collaborators/",
            {"user_id": collaborator.id},
        )

        self.client.force_authenticate(collaborator)
        response = self.client.post(self.private_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_downgraded_collaborator_loses_edit_on_public_playlist(self):
        # An invited collaborator who WAS Premium (and could edit) gets
        # downgraded to Free and must then lose edit ability, same as a
        # downgraded owner would.
        collaborator = create_verified_user("premium_gate_downgraded@test.com")
        collaborator.subscription_tier = User.SUBSCRIPTION_PREMIUM
        collaborator.save(update_fields=["subscription_tier"])

        self.client.force_authenticate(self.owner)
        self.client.post(
            f"/api/v1/playlists/{self.public_playlist_id}/collaborators/",
            {"user_id": collaborator.id},
        )

        self.client.force_authenticate(collaborator)
        add = self.client.post(self.public_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(add.status_code, status.HTTP_201_CREATED)

        collaborator.subscription_tier = User.SUBSCRIPTION_FREE
        collaborator.save(update_fields=["subscription_tier"])

        blocked = self.client.post(self.public_songs_url, {"title": "Song 2", "artist": "Artist"})
        self.assertEqual(blocked.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(blocked.data["code"], "playlist_edit_requires_premium")

    def test_downgraded_collaborator_loses_edit_on_private_playlist(self):
        # Same as above, but for a PRIVATE invited playlist — the exact
        # scenario reported as broken.
        collaborator = create_verified_user("premium_gate_downgraded_private@test.com")
        collaborator.subscription_tier = User.SUBSCRIPTION_PREMIUM
        collaborator.save(update_fields=["subscription_tier"])

        self.client.force_authenticate(self.owner)
        self.client.post(
            f"/api/v1/playlists/{self.private_playlist_id}/collaborators/",
            {"user_id": collaborator.id},
        )

        self.client.force_authenticate(collaborator)
        add = self.client.post(self.private_songs_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(add.status_code, status.HTTP_201_CREATED)

        collaborator.subscription_tier = User.SUBSCRIPTION_FREE
        collaborator.save(update_fields=["subscription_tier"])

        blocked = self.client.post(self.private_songs_url, {"title": "Song 2", "artist": "Artist"})
        self.assertEqual(blocked.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(blocked.data["code"], "playlist_edit_requires_premium")
