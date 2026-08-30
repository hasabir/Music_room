# events/tests.py — REPLACE the EventTests class with this version
# (only the _login method and its usage changes — force_authenticate
# instead of hitting the real /auth/login/ endpoint, which was getting
# throttled after ~5 calls since LoginRateThrottle's cache persists
# across all tests in the same test run)

from datetime import timedelta

from django.test import override_settings
from rest_framework.test import APITestCase
from rest_framework import status

from user.models import User
from .models import Event, Song, EventSong, Vote, EventGuest


def create_verified_user(email, password="TestPass123"):
    user = User.objects.create_user(email=email, password=password, registration_method="email")
    user.is_email_verified = True
    user.save(update_fields=["is_email_verified"])
    return user


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventTests(APITestCase):

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.other_user = create_verified_user("other@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.events_url = "/api/v1/events/"

    def _login(self, user):
        # Use force_authenticate instead of the real login endpoint —
        # avoids depending on the auth flow (already tested separately)
        # and avoids LoginRateThrottle interference across the test run.
        self.client.force_authenticate(user)

    # ---------- EVENT CREATE / VISIBILITY ----------

    def test_create_event_defaults(self):
        self._login(self.host)
        response = self.client.post(self.events_url, {"title": "Test Party"})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["visibility"], "public")
        self.assertEqual(response.data["vote_permission"], "everyone")
        self.assertEqual(response.data["song_count"], 0)
        self.assertFalse(response.data["voting_is_open"])

    def test_create_location_restricted_event_requires_fields(self):
        self._login(self.host)
        response = self.client.post(self.events_url, {
            "title": "Rooftop", "vote_permission": "location_time_restricted"
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_public_event_visible_to_stranger(self):
        self._login(self.host)
        create_resp = self.client.post(self.events_url, {"title": "Public Party", "visibility": "public"})
        event_id = create_resp.data["id"]

        self._login(self.stranger)
        response = self.client.get(f"{self.events_url}{event_id}/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_private_event_not_visible_to_stranger(self):
        self._login(self.host)
        create_resp = self.client.post(self.events_url, {"title": "Secret Party", "visibility": "private"})
        event_id = create_resp.data["id"]

        self._login(self.stranger)
        response = self.client.get(f"{self.events_url}{event_id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_only_host_can_update_event(self):
        self._login(self.host)
        create_resp = self.client.post(self.events_url, {"title": "Party"})
        event_id = create_resp.data["id"]

        self._login(self.other_user)
        response = self.client.patch(f"{self.events_url}{event_id}/", {"title": "Hijacked"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_only_host_can_delete_event(self):
        self._login(self.host)
        create_resp = self.client.post(self.events_url, {"title": "Party"})
        event_id = create_resp.data["id"]

        self._login(self.other_user)
        response = self.client.delete(f"{self.events_url}{event_id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

# Keep the rest of your existing test classes (QueueAndVotingTests,
# VotePermissionModeTests, EventGuestTests) unchanged — they already
# use force_authenticate correctly.

@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class QueueAndVotingTests(APITestCase):

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.voter1 = create_verified_user("voter1@test.com")
        self.voter2 = create_verified_user("voter2@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Test Party"})
        self.event_id = event_resp.data["id"]
        self.queue_url = f"/api/v1/events/{self.event_id}/queue/"

    def _login(self, user):
        self.client.force_authenticate(user)

    def _add_song(self, title, artist):
        return self.client.post(self.queue_url, {"title": title, "artist": artist})

    # ---------- ADD SONG ----------

    def test_add_song_creates_event_song_with_zero_votes(self):
        response = self._add_song("Blinding Lights", "The Weeknd")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["vote_count"], 0)
        # It's the only (so highest-ranked) song in the queue, so it's
        # immediately the authoritative "on air" song — see
        # `Event.sync_current_song` / `PlaybackSyncTests`.
        self.assertEqual(response.data["status"], "playing")

    def test_adding_same_song_twice_fails(self):
        self._add_song("Blinding Lights", "The Weeknd")
        response = self._add_song("Blinding Lights", "The Weeknd")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_adding_same_song_case_insensitive_reuses_catalog_entry(self):
        self._add_song("Blinding Lights", "The Weeknd")
        response = self._add_song("blinding lights", "the weeknd")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Song.objects.count(), 1)  # only one Song row created, not two

    def test_add_song_requires_access(self):
        stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.host)
        private_resp = self.client.post("/api/v1/events/", {"title": "Secret", "visibility": "private"})
        private_queue_url = f"/api/v1/events/{private_resp.data['id']}/queue/"

        self._login(stranger)
        response = self.client.post(private_queue_url, {"title": "Song", "artist": "Artist"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    # ---------- VOTING RULES ----------

    def test_voting_blocked_with_fewer_than_2_songs(self):
        add_resp = self._add_song("Song A", "Artist A")
        event_song_id = add_resp.data["id"]

        response = self.client.post(f"{self.queue_url}{event_song_id}/vote/", {})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn("At least 2 songs", response.data["detail"])

    def test_voting_allowed_with_2_or_more_songs(self):
        self._add_song("Song A", "Artist A")
        add_resp = self._add_song("Song B", "Artist B")
        event_song_id = add_resp.data["id"]

        response = self.client.post(f"{self.queue_url}{event_song_id}/vote/", {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["vote_count"], 1)

    def test_cannot_vote_twice_for_same_song(self):
        self._add_song("Song A", "Artist A")
        add_resp = self._add_song("Song B", "Artist B")
        event_song_id = add_resp.data["id"]
        vote_url = f"{self.queue_url}{event_song_id}/vote/"

        self.client.post(vote_url, {})
        response = self.client.post(vote_url, {})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Vote.objects.count(), 1)

    def test_different_users_can_vote_for_same_song(self):
        self._add_song("Song A", "Artist A")
        add_resp = self._add_song("Song B", "Artist B")
        event_song_id = add_resp.data["id"]
        vote_url = f"{self.queue_url}{event_song_id}/vote/"

        self.client.post(vote_url, {})  # host votes

        self._login(self.voter1)
        response = self.client.post(vote_url, {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["vote_count"], 2)

    def test_queue_sorted_by_vote_count_descending(self):
        add_a = self._add_song("Song A", "Artist A")
        add_b = self._add_song("Song B", "Artist B")

        # Vote for Song B twice (from two different users) so it outranks A
        vote_url_b = f"{self.queue_url}{add_b.data['id']}/vote/"
        self.client.post(vote_url_b, {})
        self._login(self.voter1)
        self.client.post(vote_url_b, {})

        response = self.client.get(self.queue_url)
        self.assertEqual(response.data[0]["song"]["title"], "Song B")
        self.assertEqual(response.data[0]["vote_count"], 2)
        self.assertEqual(response.data[1]["song"]["title"], "Song A")

    def test_retract_vote(self):
        self._add_song("Song A", "Artist A")
        add_resp = self._add_song("Song B", "Artist B")
        event_song_id = add_resp.data["id"]
        vote_url = f"{self.queue_url}{event_song_id}/vote/"

        self.client.post(vote_url, {})
        response = self.client.delete(vote_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["vote_count"], 0)

    def test_retract_vote_when_none_exists_fails(self):
        self._add_song("Song A", "Artist A")
        add_resp = self._add_song("Song B", "Artist B")
        event_song_id = add_resp.data["id"]

        response = self.client.delete(f"{self.queue_url}{event_song_id}/vote/")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_has_voted_flag_reflects_current_user(self):
        self._add_song("Song A", "Artist A")
        add_resp = self._add_song("Song B", "Artist B")
        event_song_id = add_resp.data["id"]

        self.client.post(f"{self.queue_url}{event_song_id}/vote/", {})

        response = self.client.get(self.queue_url)
        voted_song = next(s for s in response.data if s["id"] == event_song_id)
        self.assertTrue(voted_song["has_voted"])

        self._login(self.voter1)
        response = self.client.get(self.queue_url)
        voted_song = next(s for s in response.data if s["id"] == event_song_id)
        self.assertFalse(voted_song["has_voted"])


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class PlaybackSyncTests(APITestCase):
    """
    `Event.sync_current_song` is what makes the backend (not any client)
    authoritative for what's currently playing — see DECISIONS.md. These
    go through the same REST endpoints a client actually calls (rather
    than calling the model method directly) since that's what proves it's
    correctly wired into every place that can change the leader.
    """

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.voter1 = create_verified_user("voter1@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Test Party"})
        self.event_id = event_resp.data["id"]
        self.event_url = f"/api/v1/events/{self.event_id}/"
        self.queue_url = f"/api/v1/events/{self.event_id}/queue/"

    def _login(self, user):
        self.client.force_authenticate(user)

    def _add_song(self, title, artist, **extra):
        return self.client.post(self.queue_url, {"title": title, "artist": artist, **extra})

    def _backdate_current_song(self, seconds):
        """Simulate `seconds` of real time having passed since the current
        song started, as if nobody had the event open to notice."""
        event = Event.objects.get(id=self.event_id)
        event.current_song_started_at -= timedelta(seconds=seconds)
        event.save(update_fields=["current_song_started_at"])

    def test_first_song_added_becomes_current(self):
        self._add_song("Song A", "Artist A")

        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Song A")
        self.assertEqual(response.data["current_song"]["status"], "playing")
        self.assertGreaterEqual(response.data["current_position_seconds"], 0)

    def test_empty_queue_has_no_current_song(self):
        response = self.client.get(self.event_url)
        self.assertIsNone(response.data["current_song"])
        self.assertIsNone(response.data["current_position_seconds"])

    def test_position_advances_with_wall_clock_time(self):
        self._add_song("Song A", "Artist A")
        self._backdate_current_song(10)

        response = self.client.get(self.event_url)
        self.assertGreaterEqual(response.data["current_position_seconds"], 10)

    def test_song_auto_advances_once_its_time_elapses_with_nobody_watching(self):
        add_a = self._add_song("Song A", "Artist A")
        self._add_song("Song B", "Artist B")

        # Nobody calls any "mark played" endpoint — there isn't one. This
        # simulates enough wall-clock time passing (more than the default
        # 30s preview clip) while no one had the event open.
        self._backdate_current_song(31)

        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Song B")

        played_song = EventSong.objects.get(id=add_a.data["id"])
        self.assertEqual(played_song.status, "played")
        self.assertNotIn(
            "Song A", [s["song"]["title"] for s in self.client.get(self.queue_url).data]
        )

    def test_catches_up_across_multiple_elapsed_songs(self):
        self._add_song("Song A", "Artist A")
        self._add_song("Song B", "Artist B")
        self._add_song("Song C", "Artist C")

        # A ([0,30)) and B ([30,60)) fully elapse; 65s lands 5s into C's
        # ([60,90)) window, so it should be the one left current.
        self._backdate_current_song(65)

        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Song C")
        self.assertEqual(EventSong.objects.filter(status="played").count(), 2)

    def test_voting_never_interrupts_the_currently_playing_song(self):
        add_a = self._add_song("Song A", "Artist A")
        add_b = self._add_song("Song B", "Artist B")

        # Song A is current (added first, no votes yet). Vote Song B well
        # above it, still well before Song A's clip would naturally finish.
        vote_url_b = f"{self.queue_url}{add_b.data['id']}/vote/"
        self.client.post(vote_url_b, {})
        self._login(self.voter1)
        self.client.post(vote_url_b, {})

        # Song A is still on air — a vote only ever reorders who's next,
        # it never cuts off what's already playing.
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Song A")
        song_a = EventSong.objects.get(id=add_a.data["id"])
        self.assertEqual(song_a.status, "playing")

        # But the queue itself already reflects the new vote order — Song
        # B is positioned to lead once Song A's time is actually up.
        queue = self.client.get(self.queue_url).data
        self.assertEqual(queue[0]["song"]["title"], "Song B")

    def test_song_that_finishes_hands_off_to_whoever_led_the_vote_meanwhile(self):
        add_a = self._add_song("Song A", "Artist A")
        add_b = self._add_song("Song B", "Artist B")

        # Vote Song B up while Song A is still playing (no effect on
        # what's current, per the test above) ...
        self.client.post(f"{self.queue_url}{add_b.data['id']}/vote/", {})

        # ... then let Song A's time genuinely run out.
        self._backdate_current_song(31)

        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Song B")

    def test_preview_type_always_caps_at_30s_even_with_a_longer_known_duration(self):
        # A Deezer `preview` clip is physically only ~30s of audio no
        # matter what `duration_seconds` says the real commercial track's
        # length is — that metadata describes the song, not the clip, so
        # it must never stretch how long this stays "current".
        self._add_song("Long Song", "Artist A", duration_seconds=200)
        self._add_song("Song B", "Artist B")

        self._backdate_current_song(31)

        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Song B")
        long_song = EventSong.objects.get(song__title="Long Song")
        self.assertEqual(long_song.status, "played")

    def test_full_type_uses_its_own_known_duration_not_the_preview_cap(self):
        self._add_song("Long Song", "Artist A", duration_seconds=45, playback_type="full")
        self._add_song("Song B", "Artist B")

        # 31s would have retired a `preview`-type song (fixed 30s clip),
        # but this one is `full` with a real 45s duration.
        self._backdate_current_song(31)

        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Long Song")

    def test_full_type_with_no_known_duration_never_auto_advances(self):
        self._add_song("Mystery Song", "Artist A", playback_type="full")
        self._add_song("Song B", "Artist B")

        self._backdate_current_song(10_000)

        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Mystery Song")

    def test_playback_type_defaults_to_preview_when_omitted(self):
        add_a = self._add_song("Song A", "Artist A")
        event_song = EventSong.objects.get(id=add_a.data["id"])
        self.assertEqual(event_song.song.playback_type, "preview")


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class VotePermissionModeTests(APITestCase):
    """Tests specifically for invited_only vote_permission mode."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.invited_user = create_verified_user("invited@test.com")
        self.uninvited_user = create_verified_user("uninvited@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {
            "title": "Invite Only Party",
            "vote_permission": "invited_only",
        })
        self.event_id = event_resp.data["id"]
        self.queue_url = f"/api/v1/events/{self.event_id}/queue/"

        self.client.post(self.queue_url, {"title": "Song A", "artist": "Artist A"})
        add_b = self.client.post(self.queue_url, {"title": "Song B", "artist": "Artist B"})
        self.event_song_id = add_b.data["id"]

        # Invite invited_user via the guests endpoint
        self.client.post(f"/api/v1/events/{self.event_id}/guests/", {"user_id": self.invited_user.id})

    def test_invited_user_can_vote(self):
        self.client.force_authenticate(self.invited_user)
        response = self.client.post(f"{self.queue_url}{self.event_song_id}/vote/", {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_uninvited_user_cannot_vote(self):
        self.client.force_authenticate(self.uninvited_user)
        response = self.client.post(f"{self.queue_url}{self.event_song_id}/vote/", {})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_host_can_always_vote(self):
        self.client.force_authenticate(self.host)
        response = self.client.post(f"{self.queue_url}{self.event_song_id}/vote/", {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventGuestTests(APITestCase):

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.guest = create_verified_user("guest@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Private Party", "visibility": "private"})
        self.event_id = event_resp.data["id"]
        self.guests_url = f"/api/v1/events/{self.event_id}/guests/"

    def test_host_can_invite_guest(self):
        response = self.client.post(self.guests_url, {"user_id": self.guest.id})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_non_host_cannot_invite_guest(self):
        self.client.force_authenticate(self.guest)
        response = self.client.post(self.guests_url, {"user_id": self.stranger.id})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_inviting_same_guest_twice_fails(self):
        self.client.post(self.guests_url, {"user_id": self.guest.id})
        response = self.client.post(self.guests_url, {"user_id": self.guest.id})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_invited_guest_can_now_see_private_event(self):
        self.client.post(self.guests_url, {"user_id": self.guest.id})

        self.client.force_authenticate(self.guest)
        response = self.client.get(f"/api/v1/events/{self.event_id}/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_host_can_remove_guest(self):
        self.client.post(self.guests_url, {"user_id": self.guest.id})
        response = self.client.delete(f"{self.guests_url}{self.guest.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

        # confirm guest lost access
        self.client.force_authenticate(self.guest)
        response = self.client.get(f"/api/v1/events/{self.event_id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)