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


class PlaylistIsCollaboratorFieldTests(APITestCase):
    """`is_collaborator` on PlaylistSerializer — lets the client tell a
    public playlist the user already collaborates on apart from one
    they've merely discovered (no self-serve "join" exists for playlists,
    unlike events)."""

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