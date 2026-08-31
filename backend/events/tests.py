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
from .models import Event, Song, EventSong, Vote, EventGuest, EventAccessRequest


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

    def test_add_song_with_external_id_is_matched_by_external_id_not_title(self):
        # Mirrors AddSongToPlaylistSerializer matching in playlists/views.py
        # — a title/artist that exists at multiple providers must not
        # collapse into one Song row keyed off title/artist alone.
        first = self.client.post(self.queue_url, {
            "title": "Song X", "artist": "Artist X", "external_id": "audius:abc123"
        })
        song_id = first.data["song"]["id"]
        self.assertEqual(Song.objects.filter(external_id="audius:abc123").count(), 1)

        second_event = self.client.post("/api/v1/events/", {"title": "Second Party"})
        second_queue_url = f"/api/v1/events/{second_event.data['id']}/queue/"
        # Different title casing, same external_id — should resolve to the
        # exact same catalog Song, not fork a duplicate.
        second = self.client.post(second_queue_url, {
            "title": "song x", "artist": "artist x", "external_id": "audius:abc123"
        })
        self.assertEqual(second.data["song"]["id"], song_id)
        self.assertEqual(Song.objects.filter(external_id="audius:abc123").count(), 1)

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

    def test_played_song_can_be_added_again_starting_fresh(self):
        add_a = self._add_song("Song A", "Artist A")
        self._add_song("Song B", "Artist B")

        self.client.post(f"{self.queue_url}{add_a.data['id']}/vote/", {})
        self._backdate_current_song(31)

        response = self._add_song("Song A", "Artist A")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["id"], add_a.data["id"])  # same row, revived
        self.assertEqual(response.data["vote_count"], 0)  # old votes cleared
        self.assertEqual(response.data["status"], "queued")
        self.assertIn(
            "Song A", [s["song"]["title"] for s in self.client.get(self.queue_url).data]
        )

    def test_still_queued_song_cannot_be_added_again(self):
        self._add_song("Song A", "Artist A")

        response = self._add_song("Song A", "Artist A")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_played_song_can_be_revived_via_external_id_match(self):
        add_a = self._add_song("Song A", "Artist A", external_id="deezer:555")
        self._add_song("Song B", "Artist B")

        self.client.post(f"{self.queue_url}{add_a.data['id']}/vote/", {})
        self._backdate_current_song(31)

        # Re-add with different title/artist casing but the same
        # external_id — external_id-aware matching (Task 3) must still
        # resolve to the same catalog Song, so this revives the same
        # EventSong row rather than creating a stray duplicate.
        response = self._add_song("song a", "artist a", external_id="deezer:555")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["id"], add_a.data["id"])  # same row, revived
        self.assertEqual(response.data["vote_count"], 0)
        self.assertEqual(response.data["status"], "queued")
        self.assertEqual(Song.objects.filter(external_id="deezer:555").count(), 1)


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


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class VoteRetractionAccessTests(APITestCase):
    """
    Task 2: DELETE .../vote/ must re-check event visibility before
    allowing a retraction — but not the full can_user_vote gate (2-song
    minimum, location/time window don't apply to removing an existing
    vote). Uses a private + invited_only event so removing the guest
    also removes visibility, which is the only thing that should now
    block a retraction.
    """

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.guest = create_verified_user("guest@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {
            "title": "Private Invite Only",
            "visibility": "private",
            "vote_permission": "invited_only",
        })
        self.event_id = event_resp.data["id"]
        self.queue_url = f"/api/v1/events/{self.event_id}/queue/"
        self.guests_url = f"/api/v1/events/{self.event_id}/guests/"

        self.client.post(self.guests_url, {"user_id": self.guest.id})
        self.client.post(self.queue_url, {"title": "Song A", "artist": "Artist A"})
        add_b = self.client.post(self.queue_url, {"title": "Song B", "artist": "Artist B"})
        self.event_song_id = add_b.data["id"]

        self.client.force_authenticate(self.guest)
        self.client.post(f"{self.queue_url}{self.event_song_id}/vote/", {})

    def test_retract_own_vote_while_still_visible_succeeds(self):
        # Legitimate case, unaffected by the fix: the guest can still see
        # the event, so retraction proceeds normally.
        response = self.client.delete(f"{self.queue_url}{self.event_song_id}/vote/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["vote_count"], 0)

    def test_retract_vote_after_guest_access_revoked_is_forbidden(self):
        self.client.force_authenticate(self.host)
        self.client.delete(f"{self.guests_url}{self.guest.id}/")

        self.client.force_authenticate(self.guest)
        response = self.client.delete(f"{self.queue_url}{self.event_song_id}/vote/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "You do not have access to this event.")
        # The vote itself is untouched — it wasn't retracted, just blocked.
        self.assertEqual(Vote.objects.filter(event_song_id=self.event_song_id).count(), 1)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventAccessRequestTests(APITestCase):
    """Task 1: mirrors playlists' PlaylistAccessRequest flow, adapted to
    Events' host/guest model."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.requester = create_verified_user("requester@test.com")
        self.existing_guest = create_verified_user("existingguest@test.com")

        self.client.force_authenticate(self.host)
        private_resp = self.client.post("/api/v1/events/", {"title": "Private Party", "visibility": "private"})
        self.event_id = private_resp.data["id"]
        self.access_requests_url = f"/api/v1/events/{self.event_id}/access-requests/"
        self.mine_url = f"{self.access_requests_url}mine/"

        self.client.post(f"/api/v1/events/{self.event_id}/guests/", {"user_id": self.existing_guest.id})

        public_resp = self.client.post("/api/v1/events/", {"title": "Public Party", "visibility": "public"})
        self.public_event_id = public_resp.data["id"]

    def _decide_url(self, request_id):
        return f"{self.access_requests_url}{request_id}/decide/"

    # ---------- CREATE ----------

    def test_requester_can_request_access_to_private_event(self):
        self.client.force_authenticate(self.requester)
        response = self.client.post(self.access_requests_url, {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["status"], "pending")

    def test_host_cannot_request_access_to_own_event(self):
        self.client.force_authenticate(self.host)
        response = self.client.post(self.access_requests_url, {})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["detail"], "You already own this event.")

    def test_existing_guest_cannot_request_access(self):
        self.client.force_authenticate(self.existing_guest)
        response = self.client.post(self.access_requests_url, {})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["detail"], "You already have access to this event.")

    def test_duplicate_pending_request_is_idempotent(self):
        self.client.force_authenticate(self.requester)
        first = self.client.post(self.access_requests_url, {})
        second = self.client.post(self.access_requests_url, {})
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertEqual(second.data["id"], first.data["id"])
        self.assertEqual(EventAccessRequest.objects.count(), 1)

    def test_cannot_request_access_to_a_public_event(self):
        self.client.force_authenticate(self.requester)
        response = self.client.post(f"/api/v1/events/{self.public_event_id}/access-requests/", {})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("public", response.data["detail"])

    # ---------- LIST ----------

    def test_only_host_can_list_access_requests(self):
        self.client.force_authenticate(self.requester)
        self.client.post(self.access_requests_url, {})

        response = self.client.get(self.access_requests_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

        self.client.force_authenticate(self.host)
        response = self.client.get(self.access_requests_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)

    # ---------- MINE ----------

    def test_mine_returns_404_when_no_request_exists(self):
        self.client.force_authenticate(self.requester)
        response = self.client.get(self.mine_url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_mine_returns_most_recent_request(self):
        self.client.force_authenticate(self.requester)
        self.client.post(self.access_requests_url, {})
        response = self.client.get(self.mine_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "pending")

    def test_cancel_pending_request(self):
        self.client.force_authenticate(self.requester)
        self.client.post(self.access_requests_url, {})
        response = self.client.delete(self.mine_url)
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(EventAccessRequest.objects.count(), 0)

    def test_cancel_with_no_pending_request_fails(self):
        self.client.force_authenticate(self.requester)
        response = self.client.delete(self.mine_url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    # ---------- DECIDE ----------

    def test_non_host_cannot_decide(self):
        self.client.force_authenticate(self.requester)
        create_resp = self.client.post(self.access_requests_url, {})

        response = self.client.post(self._decide_url(create_resp.data["id"]), {"approve": True})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_approve_creates_guest_and_grants_visibility(self):
        self.client.force_authenticate(self.requester)
        create_resp = self.client.post(self.access_requests_url, {})

        self.client.force_authenticate(self.host)
        response = self.client.post(self._decide_url(create_resp.data["id"]), {"approve": True})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "approved")
        self.assertTrue(EventGuest.objects.filter(event_id=self.event_id, guest=self.requester).exists())

        self.client.force_authenticate(self.requester)
        response = self.client.get(f"/api/v1/events/{self.event_id}/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_deny_does_not_create_guest(self):
        self.client.force_authenticate(self.requester)
        create_resp = self.client.post(self.access_requests_url, {})

        self.client.force_authenticate(self.host)
        response = self.client.post(self._decide_url(create_resp.data["id"]), {"approve": False})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "denied")
        self.assertFalse(EventGuest.objects.filter(event_id=self.event_id, guest=self.requester).exists())

        self.client.force_authenticate(self.requester)
        response = self.client.get(f"/api/v1/events/{self.event_id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_deciding_an_already_decided_request_fails(self):
        self.client.force_authenticate(self.requester)
        create_resp = self.client.post(self.access_requests_url, {})

        self.client.force_authenticate(self.host)
        self.client.post(self._decide_url(create_resp.data["id"]), {"approve": True})
        response = self.client.post(self._decide_url(create_resp.data["id"]), {"approve": True})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_denied_request_can_be_re_requested(self):
        self.client.force_authenticate(self.requester)
        create_resp = self.client.post(self.access_requests_url, {})

        self.client.force_authenticate(self.host)
        self.client.post(self._decide_url(create_resp.data["id"]), {"approve": False})

        self.client.force_authenticate(self.requester)
        response = self.client.post(self.access_requests_url, {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertNotEqual(response.data["id"], create_resp.data["id"])


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventGuestRsvpTests(APITestCase):
    """RSVP status on EventGuest — POST /events/<event_id>/guests/respond/."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.guest = create_verified_user("guest@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Private Party", "visibility": "private"})
        self.event_id = event_resp.data["id"]
        self.guests_url = f"/api/v1/events/{self.event_id}/guests/"
        self.respond_url = f"/api/v1/events/{self.event_id}/guests/respond/"

    def test_fresh_invite_defaults_to_pending(self):
        response = self.client.post(self.guests_url, {"user_id": self.guest.id})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["rsvp_status"], "pending")

    def test_guest_can_accept_invitation(self):
        self.client.post(self.guests_url, {"user_id": self.guest.id})

        self.client.force_authenticate(self.guest)
        response = self.client.post(self.respond_url, {"response": "accepted"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["rsvp_status"], "accepted")
        self.assertEqual(
            EventGuest.objects.get(event_id=self.event_id, guest=self.guest).rsvp_status,
            "accepted",
        )

    def test_guest_can_decline_invitation(self):
        self.client.post(self.guests_url, {"user_id": self.guest.id})

        self.client.force_authenticate(self.guest)
        response = self.client.post(self.respond_url, {"response": "declined"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["rsvp_status"], "declined")

    def test_guest_can_change_an_existing_response(self):
        self.client.post(self.guests_url, {"user_id": self.guest.id})

        self.client.force_authenticate(self.guest)
        self.client.post(self.respond_url, {"response": "accepted"})
        response = self.client.post(self.respond_url, {"response": "declined"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["rsvp_status"], "declined")
        self.assertEqual(
            EventGuest.objects.get(event_id=self.event_id, guest=self.guest).rsvp_status,
            "declined",
        )

    def test_responding_without_an_invitation_fails(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.post(self.respond_url, {"response": "accepted"})
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data["detail"], "You have not been invited to this event.")

    def test_invalid_response_value_fails(self):
        self.client.post(self.guests_url, {"user_id": self.guest.id})

        self.client.force_authenticate(self.guest)
        response = self.client.post(self.respond_url, {"response": "maybe"})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["detail"], "Response must be 'accepted' or 'declined'.")
        # Unaffected by the bad request — still pending.
        self.assertEqual(
            EventGuest.objects.get(event_id=self.event_id, guest=self.guest).rsvp_status,
            "pending",
        )

    def test_host_cannot_respond_on_behalf_of_another_guest(self):
        # There's no user_id in the request — respond/ always targets the
        # caller's own invitation via request.user, so the host responding
        # here is answered against their own (nonexistent) invitation, not
        # the actual guest's.
        self.client.post(self.guests_url, {"user_id": self.guest.id})

        self.client.force_authenticate(self.host)
        response = self.client.post(self.respond_url, {"response": "accepted"})
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(
            EventGuest.objects.get(event_id=self.event_id, guest=self.guest).rsvp_status,
            "pending",
        )


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventGuestListFilterTests(APITestCase):
    """GET /events/<event_id>/guests/?status=... — read-only filtering by
    rsvp_status, on top of the existing (unchanged) visibility rule."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.accepted_guest = create_verified_user("accepted@test.com")
        self.declined_guest = create_verified_user("declined@test.com")
        self.pending_guest = create_verified_user("pending@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Private Party", "visibility": "private"})
        self.event_id = event_resp.data["id"]
        self.guests_url = f"/api/v1/events/{self.event_id}/guests/"
        self.respond_url = f"/api/v1/events/{self.event_id}/guests/respond/"

        self.client.post(self.guests_url, {"user_id": self.accepted_guest.id})
        self.client.post(self.guests_url, {"user_id": self.declined_guest.id})
        self.client.post(self.guests_url, {"user_id": self.pending_guest.id})

        self.client.force_authenticate(self.accepted_guest)
        self.client.post(self.respond_url, {"response": "accepted"})

        self.client.force_authenticate(self.declined_guest)
        self.client.post(self.respond_url, {"response": "declined"})
        # pending_guest never responds — stays "pending".

        self.client.force_authenticate(self.host)

    def test_unfiltered_list_returns_all_guests_regardless_of_status(self):
        response = self.client.get(self.guests_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 3)

    def test_filter_by_accepted(self):
        response = self.client.get(f"{self.guests_url}?status=accepted")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["guest_email"], "accepted@test.com")

    def test_filter_by_declined(self):
        response = self.client.get(f"{self.guests_url}?status=declined")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["guest_email"], "declined@test.com")

    def test_filter_by_pending(self):
        response = self.client.get(f"{self.guests_url}?status=pending")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["guest_email"], "pending@test.com")

    def test_invalid_status_filter_fails(self):
        response = self.client.get(f"{self.guests_url}?status=maybe")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["detail"], "Invalid status filter.")

    def test_guest_list_visibility_unchanged_for_stranger_on_private_event(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.guests_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventAttendeeListTests(APITestCase):
    """GET /events/<event_id>/attendees/ — the EventMembership list."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.member1 = create_verified_user("member1@test.com")
        self.member2 = create_verified_user("member2@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.host)
        public_resp = self.client.post("/api/v1/events/", {"title": "Public Party", "visibility": "public"})
        self.public_event_id = public_resp.data["id"]
        self.public_attendees_url = f"/api/v1/events/{self.public_event_id}/attendees/"

        private_resp = self.client.post("/api/v1/events/", {"title": "Private Party", "visibility": "private"})
        self.private_event_id = private_resp.data["id"]
        self.private_attendees_url = f"/api/v1/events/{self.private_event_id}/attendees/"

        self.client.force_authenticate(self.member1)
        self.client.post(f"/api/v1/events/{self.public_event_id}/join/", {})

        self.client.force_authenticate(self.member2)
        self.client.post(f"/api/v1/events/{self.public_event_id}/join/", {})

    def test_attendee_list_for_public_event_with_joined_members(self):
        self.client.force_authenticate(self.host)
        response = self.client.get(self.public_attendees_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 2)
        emails = {row["member_email"] for row in response.data}
        self.assertEqual(emails, {"member1@test.com", "member2@test.com"})
        self.assertIn("joined_at", response.data[0])
        self.assertIn("member", response.data[0])

    def test_attendee_list_for_private_event_is_empty_not_error(self):
        # Private-event guests never get an EventMembership row (that's
        # public-events-only, by design) — so this must return an empty
        # list, not a 403 or a special error, for someone who CAN see it.
        self.client.force_authenticate(self.host)
        response = self.client.get(self.private_attendees_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])

    def test_attendee_list_visibility_enforced_for_private_event(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.private_attendees_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_attendee_list_visible_to_anyone_for_public_event(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.public_attendees_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)