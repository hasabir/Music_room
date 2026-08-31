# events/tests.py — REPLACE the EventTests class with this version
# (only the _login method and its usage changes — force_authenticate
# instead of hitting the real /auth/login/ endpoint, which was getting
# throttled after ~5 calls since LoginRateThrottle's cache persists
# across all tests in the same test run)

from datetime import timedelta

from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework import status

from user.models import User
from .models import Event, Song, EventSong, Vote, EventGuest, EventAccessRequest, EventMembership


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

    def test_time_restriction_enabled_without_fields_fails(self):
        self._login(self.host)
        response = self.client.post(self.events_url, {
            "title": "Rooftop", "time_restriction_enabled": True,
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        detail = response.data["detail"][0]
        self.assertIn("voting_opens_at", detail)
        self.assertIn("voting_closes_at", detail)
        # Location restriction is off — its fields must never be named here.
        self.assertNotIn("venue_center_latitude", detail)

    def test_location_restriction_enabled_without_fields_fails(self):
        self._login(self.host)
        response = self.client.post(self.events_url, {
            "title": "Rooftop", "location_restriction_enabled": True,
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        detail = response.data["detail"][0]
        self.assertIn("venue_center_latitude", detail)
        self.assertIn("venue_center_longitude", detail)
        self.assertIn("allowed_distance_meters", detail)
        # Time restriction is off — its fields must never be named here.
        self.assertNotIn("voting_opens_at", detail)

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

    def test_tied_vote_count_ranks_whoever_reached_it_first(self):
        # Song B reaches 1 vote before Song A does, even though Song A
        # was ADDED to the queue first — the tie-break is "who reached
        # this vote count first", not queue/add order.
        add_a = self._add_song("Song A", "Artist A")
        add_b = self._add_song("Song B", "Artist B")
        add_c = self._add_song("Song C", "Artist C")  # stays at 0 votes

        self.client.post(f"{self.queue_url}{add_b.data['id']}/vote/", {})
        self.client.post(f"{self.queue_url}{add_a.data['id']}/vote/", {})

        response = self.client.get(self.queue_url)
        titles = [s["song"]["title"] for s in response.data]
        self.assertEqual(titles, ["Song B", "Song A", "Song C"])
        self.assertEqual(response.data[0]["vote_count"], 1)
        self.assertEqual(response.data[1]["vote_count"], 1)

    def test_retracting_and_recasting_a_vote_resets_its_tiebreak_moment(self):
        # Song A reaches 1 vote first (leads). Its only vote is then
        # retracted and immediately re-cast by someone else — Song A is
        # back at 1 vote, but only just now, *after* Song B already got
        # there. Song B must lead now: reaching a count once, dipping
        # below it, and climbing back to the same count later is not the
        # same as having held it continuously since the first time.
        add_a = self._add_song("Song A", "Artist A")
        add_b = self._add_song("Song B", "Artist B")
        vote_url_a = f"{self.queue_url}{add_a.data['id']}/vote/"
        vote_url_b = f"{self.queue_url}{add_b.data['id']}/vote/"

        self.client.post(vote_url_a, {})  # host votes A -> A reaches 1 first
        self._login(self.voter1)
        self.client.post(vote_url_b, {})  # voter1 votes B -> B reaches 1 second

        response = self.client.get(self.queue_url)
        self.assertEqual(response.data[0]["song"]["title"], "Song A")

        self._login(self.host)
        self.client.delete(vote_url_a)  # A drops to 0
        self._login(self.voter2)
        self.client.post(vote_url_a, {})  # A climbs back to 1, later than B's 1

        response = self.client.get(self.queue_url)
        titles = [s["song"]["title"] for s in response.data]
        self.assertEqual(titles, ["Song B", "Song A"])

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

    def test_current_song_tie_break_goes_to_whoever_reached_the_vote_count_first(self):
        # Song X plays first (sole song, 0 votes) and holds the lead
        # while it plays — voting never interrupts it, per the test
        # above. Behind it, Song B is added before Song A (so Song B
        # would win an add-order tie-break), but Song A reaches 1 vote
        # before Song B does. Once Song X's time is up and a new leader
        # has to be picked from scratch, Song A must win the tie.
        self._add_song("Song X", "Artist X")
        add_b = self._add_song("Song B", "Artist B")
        add_a = self._add_song("Song A", "Artist A")

        self.client.post(f"{self.queue_url}{add_a.data['id']}/vote/", {})
        self.client.post(f"{self.queue_url}{add_b.data['id']}/vote/", {})

        self._backdate_current_song(31)  # Song X's clip has now finished

        response = self.client.get(self.event_url)
        self.assertEqual(response.data["current_song"]["song"]["title"], "Song A")

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

    def test_host_can_remove_a_guest_regardless_of_rsvp_status(self):
        # DELETE .../guests/<user_id>/ filters only on (event, guest) — it
        # was never status-aware to begin with, so removal must behave
        # identically no matter which of the three statuses the target is
        # currently in.
        for target in (self.pending_guest, self.accepted_guest, self.declined_guest):
            with self.subTest(rsvp_status=target):
                response = self.client.delete(f"{self.guests_url}{target.id}/")
                self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
                self.assertFalse(
                    EventGuest.objects.filter(event_id=self.event_id, guest=target).exists()
                )


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


class EventIsMemberFieldTests(APITestCase):
    """`is_member` on EventSerializer — lets the client tell a public event
    the user already joined apart from one they haven't discovered yet."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.joiner = create_verified_user("joiner@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.host)
        create_resp = self.client.post(
            "/api/v1/events/", {"title": "Public Party", "visibility": "public"}
        )
        self.event_id = create_resp.data["id"]
        self.detail_url = f"/api/v1/events/{self.event_id}/"

        self.client.force_authenticate(self.joiner)
        self.client.post(f"/api/v1/events/{self.event_id}/join/", {})

    def test_is_member_true_after_joining(self):
        self.client.force_authenticate(self.joiner)
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["is_member"])

    def test_is_member_false_for_stranger_who_has_not_joined(self):
        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["is_member"])

    def test_is_member_false_for_host(self):
        # The host can't self-join their own event (EventJoinView rejects
        # it), so this should read false rather than ever being true.
        self.client.force_authenticate(self.host)
        response = self.client.get(self.detail_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["is_member"])

    def test_is_member_reflected_in_list_endpoint(self):
        self.client.force_authenticate(self.joiner)
        response = self.client.get("/api/v1/events/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        event = next(e for e in response.data["results"] if e["id"] == self.event_id)
        self.assertTrue(event["is_member"])


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventAttendeeRemovalTests(APITestCase):
    """DELETE /events/<event_id>/attendees/<user_id>/ — host-only removal
    of an EventMembership, independent of any EventGuest the same user
    might separately hold."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.member = create_verified_user("member@test.com")
        self.other_user = create_verified_user("other@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Public Party", "visibility": "public"})
        self.event_id = event_resp.data["id"]
        self.attendees_url = f"/api/v1/events/{self.event_id}/attendees/"
        self.guests_url = f"/api/v1/events/{self.event_id}/guests/"

        self.client.force_authenticate(self.member)
        self.client.post(f"/api/v1/events/{self.event_id}/join/", {})

    def test_host_can_remove_an_attendee(self):
        self.client.force_authenticate(self.host)
        response = self.client.delete(f"{self.attendees_url}{self.member.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(
            EventMembership.objects.filter(event_id=self.event_id, member=self.member).exists()
        )

    def test_non_host_cannot_remove_an_attendee(self):
        self.client.force_authenticate(self.other_user)
        response = self.client.delete(f"{self.attendees_url}{self.member.id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "Only the host can remove attendees.")
        self.assertTrue(
            EventMembership.objects.filter(event_id=self.event_id, member=self.member).exists()
        )

    def test_removing_a_non_existent_attendee_fails(self):
        self.client.force_authenticate(self.host)
        response = self.client.delete(f"{self.attendees_url}{self.other_user.id}/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data["detail"], "This user has not joined the event.")

    def test_removing_attendee_and_guest_for_same_user_are_independent(self):
        # Give the same user both an EventGuest row (host-invited) and the
        # EventMembership from setUp (self-joined) — removing one must not
        # touch the other, since they're independent lists/records.
        self.client.force_authenticate(self.host)
        self.client.post(self.guests_url, {"user_id": self.member.id})
        self.assertTrue(EventGuest.objects.filter(event_id=self.event_id, guest=self.member).exists())
        self.assertTrue(EventMembership.objects.filter(event_id=self.event_id, member=self.member).exists())

        # Remove the attendee (EventMembership) — the EventGuest row survives.
        response = self.client.delete(f"{self.attendees_url}{self.member.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(EventMembership.objects.filter(event_id=self.event_id, member=self.member).exists())
        self.assertTrue(EventGuest.objects.filter(event_id=self.event_id, guest=self.member).exists())

        # Now remove the guest (EventGuest) too — independent action, no
        # EventMembership left to be affected either way.
        response = self.client.delete(f"{self.guests_url}{self.member.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(EventGuest.objects.filter(event_id=self.event_id, guest=self.member).exists())


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventRestrictionCreateValidationTests(APITestCase):
    """Composable time/location restriction toggles — creation-time
    required-fields validation, each independent of the other."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.client.force_authenticate(self.host)
        self.events_url = "/api/v1/events/"

    def test_neither_restriction_enabled_needs_no_extra_fields(self):
        response = self.client.post(self.events_url, {"title": "Open Party"})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertFalse(response.data["time_restriction_enabled"])
        self.assertFalse(response.data["location_restriction_enabled"])

    def test_time_only_with_all_fields_succeeds(self):
        response = self.client.post(self.events_url, {
            "title": "Timed Party",
            "time_restriction_enabled": True,
            "voting_opens_at": "2026-09-01T16:00:00Z",
            "voting_closes_at": "2026-09-01T18:00:00Z",
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data["time_restriction_enabled"])
        self.assertFalse(response.data["location_restriction_enabled"])

    def test_time_only_with_partial_fields_fails_naming_only_the_missing_one(self):
        response = self.client.post(self.events_url, {
            "title": "Timed Party",
            "time_restriction_enabled": True,
            "voting_opens_at": "2026-09-01T16:00:00Z",
            # voting_closes_at deliberately omitted
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        detail = response.data["detail"][0]
        self.assertIn("voting_closes_at", detail)
        self.assertNotIn("voting_opens_at", detail)

    def test_location_only_with_all_fields_succeeds(self):
        response = self.client.post(self.events_url, {
            "title": "Venue Party",
            "location_restriction_enabled": True,
            "venue_center_latitude": 33.5731,
            "venue_center_longitude": -7.5898,
            "allowed_distance_meters": 200,
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertFalse(response.data["time_restriction_enabled"])
        self.assertTrue(response.data["location_restriction_enabled"])

    def test_location_only_with_partial_fields_fails_naming_only_missing_ones(self):
        response = self.client.post(self.events_url, {
            "title": "Venue Party",
            "location_restriction_enabled": True,
            "venue_center_latitude": 33.5731,
            # venue_center_longitude and allowed_distance_meters omitted
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        detail = response.data["detail"][0]
        self.assertIn("venue_center_longitude", detail)
        self.assertIn("allowed_distance_meters", detail)
        self.assertNotIn("voting_opens_at", detail)

    def test_both_restrictions_enabled_with_all_fields_succeeds(self):
        response = self.client.post(self.events_url, {
            "title": "Full Party",
            "time_restriction_enabled": True,
            "voting_opens_at": "2026-09-01T16:00:00Z",
            "voting_closes_at": "2026-09-01T18:00:00Z",
            "location_restriction_enabled": True,
            "venue_center_latitude": 33.5731,
            "venue_center_longitude": -7.5898,
            "allowed_distance_meters": 200,
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data["time_restriction_enabled"])
        self.assertTrue(response.data["location_restriction_enabled"])

    def test_both_restrictions_enabled_missing_both_fields_reports_time_first(self):
        # Time is validated before location (see EventSerializer.validate),
        # so with both blocks missing fields, only the time message
        # surfaces — the request must be resubmitted to see the location
        # one, matching can_user_vote's own time-before-location ordering.
        response = self.client.post(self.events_url, {
            "title": "Full Party",
            "time_restriction_enabled": True,
            "location_restriction_enabled": True,
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        detail = response.data["detail"][0]
        self.assertIn("voting_opens_at", detail)
        self.assertNotIn("venue_center_latitude", detail)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventRestrictionPatchTests(APITestCase):
    """PATCH /events/<pk>/ — host can toggle restrictions on/off at any
    time; partial patches must validate against the merged (incoming +
    existing) state, not treat untouched fields as missing."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.client.force_authenticate(self.host)
        create_resp = self.client.post("/api/v1/events/", {"title": "Party"})
        self.event_id = create_resp.data["id"]
        self.event_url = f"/api/v1/events/{self.event_id}/"

    def test_patch_enables_time_restriction_with_fields(self):
        response = self.client.patch(self.event_url, {
            "time_restriction_enabled": True,
            "voting_opens_at": "2026-09-01T16:00:00Z",
            "voting_closes_at": "2026-09-01T18:00:00Z",
        })
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["time_restriction_enabled"])

    def test_patch_enabling_time_restriction_without_fields_fails(self):
        response = self.client.patch(self.event_url, {"time_restriction_enabled": True})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_partial_patch_on_already_restricted_event_does_not_spuriously_fail(self):
        self.client.patch(self.event_url, {
            "time_restriction_enabled": True,
            "voting_opens_at": "2026-09-01T16:00:00Z",
            "voting_closes_at": "2026-09-01T18:00:00Z",
        })
        # A patch that only touches an unrelated field must validate
        # against the event's already-saved restriction fields, not treat
        # them as missing just because this request didn't resend them.
        response = self.client.patch(self.event_url, {"title": "Renamed Party"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["title"], "Renamed Party")
        self.assertTrue(response.data["time_restriction_enabled"])

    def test_patch_can_disable_a_previously_enabled_restriction(self):
        self.client.patch(self.event_url, {
            "location_restriction_enabled": True,
            "venue_center_latitude": 33.5731,
            "venue_center_longitude": -7.5898,
            "allowed_distance_meters": 200,
        })
        response = self.client.patch(self.event_url, {"location_restriction_enabled": False})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["location_restriction_enabled"])

    def test_toggles_are_independent_of_each_other(self):
        response = self.client.patch(self.event_url, {
            "time_restriction_enabled": True,
            "voting_opens_at": "2026-09-01T16:00:00Z",
            "voting_closes_at": "2026-09-01T18:00:00Z",
        })
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["time_restriction_enabled"])
        self.assertFalse(response.data["location_restriction_enabled"])


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class VoteRestrictionCombinationTests(APITestCase):
    """can_user_vote — the two restriction toggles are independent and
    composable, layered on top of vote_permission="everyone" here so
    those checks alone determine pass/fail."""

    VENUE_LAT, VENUE_LON = 33.5731, -7.5898
    FAR_LAT, FAR_LON = 40.7128, -74.0060  # New York — nowhere near the venue

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.voter = create_verified_user("voter@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Test Party"})
        self.event_id = event_resp.data["id"]
        self.event_url = f"/api/v1/events/{self.event_id}/"
        self.queue_url = f"/api/v1/events/{self.event_id}/queue/"

        self.client.post(self.queue_url, {"title": "Song A", "artist": "Artist A"})
        add_b = self.client.post(self.queue_url, {"title": "Song B", "artist": "Artist B"})
        self.event_song_id = add_b.data["id"]
        self.vote_url = f"{self.queue_url}{self.event_song_id}/vote/"

    def _enable_time(self, opens_at, closes_at):
        self.client.patch(self.event_url, {
            "time_restriction_enabled": True,
            "voting_opens_at": opens_at,
            "voting_closes_at": closes_at,
        })

    def _enable_location(self):
        self.client.patch(self.event_url, {
            "location_restriction_enabled": True,
            "venue_center_latitude": self.VENUE_LAT,
            "venue_center_longitude": self.VENUE_LON,
            "allowed_distance_meters": 200,
        })

    def test_time_only_blocks_outside_window_even_with_no_location_sent(self):
        now = timezone.now()
        self._enable_time(now - timedelta(hours=2), now - timedelta(hours=1))  # already closed

        self.client.force_authenticate(self.voter)
        response = self.client.post(self.vote_url, {})  # no lat/long — location isn't enabled
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "Voting has closed for this event.")

    def test_time_only_allows_voting_inside_window(self):
        now = timezone.now()
        self._enable_time(now - timedelta(hours=1), now + timedelta(hours=1))

        self.client.force_authenticate(self.voter)
        response = self.client.post(self.vote_url, {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_location_only_blocks_when_too_far_even_with_time_disabled(self):
        self._enable_location()

        self.client.force_authenticate(self.voter)
        response = self.client.post(self.vote_url, {
            "latitude": self.FAR_LAT, "longitude": self.FAR_LON,
        }, format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "You must be near the event venue to vote.")

    def test_location_only_requires_coordinates_when_enabled(self):
        self._enable_location()

        self.client.force_authenticate(self.voter)
        response = self.client.post(self.vote_url, {})  # no coordinates at all
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "Your location is required to vote on this event.")

    def test_location_only_allows_voting_near_venue(self):
        self._enable_location()

        self.client.force_authenticate(self.voter)
        response = self.client.post(self.vote_url, {
            "latitude": self.VENUE_LAT, "longitude": self.VENUE_LON,
        }, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_both_enabled_and_both_satisfied_succeeds(self):
        now = timezone.now()
        self._enable_time(now - timedelta(hours=1), now + timedelta(hours=1))
        self._enable_location()

        self.client.force_authenticate(self.voter)
        response = self.client.post(self.vote_url, {
            "latitude": self.VENUE_LAT, "longitude": self.VENUE_LON,
        }, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_both_enabled_time_passes_location_fails(self):
        now = timezone.now()
        self._enable_time(now - timedelta(hours=1), now + timedelta(hours=1))
        self._enable_location()

        self.client.force_authenticate(self.voter)
        response = self.client.post(self.vote_url, {
            "latitude": self.FAR_LAT, "longitude": self.FAR_LON,
        }, format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "You must be near the event venue to vote.")

    def test_both_enabled_and_both_fail_surfaces_time_message_first(self):
        now = timezone.now()
        self._enable_time(now - timedelta(hours=2), now - timedelta(hours=1))  # closed
        self._enable_location()

        self.client.force_authenticate(self.voter)
        response = self.client.post(self.vote_url, {
            "latitude": self.FAR_LAT, "longitude": self.FAR_LON,  # also fails location
        }, format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "Voting has closed for this event.")


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class LocationTimeRestrictedMigrationTests(APITestCase):
    """
    Data migration 0012_migrate_location_time_restricted_events: converts
    a pre-existing event using the old combined `location_time_restricted`
    vote_permission value into the new composable-restriction shape.

    Calls the migration's own migrate_forward function directly (imported
    via importlib, since its module name starts with a digit) rather than
    re-implementing its logic — this is testing the actual migration code,
    not a copy of it. The live app registry is fine to pass in here since
    migrate_forward only touches fields ("vote_permission",
    "time_restriction_enabled", "location_restriction_enabled") that are
    unchanged between the migration's historical state and HEAD.
    """

    def _run_migration(self):
        import importlib
        from django.apps import apps as django_apps

        migration_module = importlib.import_module(
            "events.migrations.0012_migrate_location_time_restricted_events"
        )
        migration_module.migrate_forward(django_apps, None)

    def test_migration_converts_a_location_time_restricted_event(self):
        host = create_verified_user("host@test.com")
        event = Event.objects.create(host=host, title="Legacy Restricted Event")
        opens_at = timezone.now()
        closes_at = opens_at + timedelta(hours=2)
        # Simulate a genuinely pre-migration row: `choices` on a CharField
        # is not DB-enforced, so this write succeeds even though the
        # current model no longer lists this value — exactly like a real
        # un-migrated row already sitting in the database.
        Event.objects.filter(id=event.id).update(
            vote_permission="location_time_restricted",
            time_restriction_enabled=False,
            location_restriction_enabled=False,
            venue_center_latitude=33.5731,
            venue_center_longitude=-7.5898,
            allowed_distance_meters=150,
            voting_opens_at=opens_at,
            voting_closes_at=closes_at,
        )

        self._run_migration()

        event.refresh_from_db()
        self.assertEqual(event.vote_permission, "invited_only")
        self.assertTrue(event.time_restriction_enabled)
        self.assertTrue(event.location_restriction_enabled)
        self.assertEqual(event.venue_center_latitude, 33.5731)
        self.assertEqual(event.venue_center_longitude, -7.5898)
        self.assertEqual(event.allowed_distance_meters, 150)
        self.assertEqual(event.voting_opens_at, opens_at)
        self.assertEqual(event.voting_closes_at, closes_at)

    def test_migration_leaves_unrelated_events_untouched(self):
        host = create_verified_user("host@test.com")
        untouched = Event.objects.create(host=host, title="Normal Event", vote_permission="everyone")
        invited = Event.objects.create(host=host, title="Invited Party", vote_permission="invited_only")

        self._run_migration()

        untouched.refresh_from_db()
        invited.refresh_from_db()
        self.assertEqual(untouched.vote_permission, "everyone")
        self.assertFalse(untouched.time_restriction_enabled)
        self.assertFalse(untouched.location_restriction_enabled)
        self.assertEqual(invited.vote_permission, "invited_only")
        self.assertFalse(invited.time_restriction_enabled)
        self.assertFalse(invited.location_restriction_enabled)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventStatusTests(APITestCase):
    """Event.status (live/closed/canceled): host-only to change; canceled
    locks out everyone but the host, even someone who'd already joined or
    been invited; closed only blocks new track suggestions — entry and
    voting on the existing queue keep working."""

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.guest = create_verified_user("guest@test.com")
        self.member = create_verified_user("member@test.com")
        self.stranger = create_verified_user("stranger@test.com")

        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Test Party", "visibility": "public"})
        self.event_id = event_resp.data["id"]
        self.event_url = f"/api/v1/events/{self.event_id}/"
        self.queue_url = f"/api/v1/events/{self.event_id}/queue/"
        self.guests_url = f"/api/v1/events/{self.event_id}/guests/"
        self.join_url = f"/api/v1/events/{self.event_id}/join/"

        self.client.post(self.guests_url, {"user_id": self.guest.id})

        self.client.force_authenticate(self.member)
        self.client.post(self.join_url, {})

        self.client.force_authenticate(self.host)

    def _set_status(self, value):
        return self.client.patch(self.event_url, {"status": value})

    # ---------- host-only to change ----------

    def test_default_status_is_live(self):
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["status"], "live")

    def test_host_can_close_event(self):
        response = self._set_status("closed")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "closed")

    def test_host_can_cancel_event(self):
        response = self._set_status("canceled")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "canceled")

    def test_non_host_cannot_change_status(self):
        self.client.force_authenticate(self.guest)
        response = self.client.patch(self.event_url, {"status": "canceled"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        event = Event.objects.get(id=self.event_id)
        self.assertEqual(event.status, "live")

    # ---------- canceled: nobody but the host can enter ----------

    def test_canceled_event_blocks_a_stranger(self):
        self._set_status("canceled")
        self.client.force_authenticate(self.stranger)
        response = self.client.get(self.event_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_canceled_event_blocks_a_previously_invited_guest(self):
        self._set_status("canceled")
        self.client.force_authenticate(self.guest)
        response = self.client.get(self.event_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_canceled_event_blocks_a_previously_joined_member(self):
        self._set_status("canceled")
        self.client.force_authenticate(self.member)
        response = self.client.get(self.event_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_canceled_event_still_visible_to_the_host(self):
        self._set_status("canceled")
        response = self.client.get(self.event_url)  # still authenticated as host
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_canceled_event_blocks_new_joins(self):
        self._set_status("canceled")
        self.client.force_authenticate(self.stranger)
        response = self.client.post(self.join_url, {})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "This event has been canceled.")

    def test_canceled_event_blocks_queue_view_for_a_former_member(self):
        self._set_status("canceled")
        self.client.force_authenticate(self.member)
        response = self.client.get(self.queue_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_canceled_event_blocks_guest_list_view_for_a_former_guest(self):
        self._set_status("canceled")
        self.client.force_authenticate(self.guest)
        response = self.client.get(self.guests_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_canceled_event_blocks_adding_tracks_even_for_the_host(self):
        self._set_status("canceled")
        response = self.client.post(self.queue_url, {"title": "Song A", "artist": "Artist A"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data["detail"], "This event has been canceled.")

    # ---------- closed: entry stays open, track suggestions don't ----------

    def test_closed_event_still_visible_to_a_member(self):
        self._set_status("closed")
        self.client.force_authenticate(self.member)
        response = self.client.get(self.event_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_closed_event_still_joinable(self):
        self._set_status("closed")
        self.client.force_authenticate(self.stranger)
        response = self.client.post(self.join_url, {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_closed_event_blocks_new_track_suggestions(self):
        self._set_status("closed")
        self.client.force_authenticate(self.member)
        response = self.client.post(self.queue_url, {"title": "Song A", "artist": "Artist A"})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(
            response.data["detail"],
            "This event is closed — new tracks can no longer be suggested.",
        )

    def test_closed_event_still_allows_voting_on_the_existing_queue(self):
        # Songs go in while still live, then the event closes — voting on
        # what's already queued must keep working even though nothing new
        # can be suggested anymore.
        self.client.post(self.queue_url, {"title": "Song A", "artist": "Artist A"})
        add_b = self.client.post(self.queue_url, {"title": "Song B", "artist": "Artist B"})
        self._set_status("closed")

        self.client.force_authenticate(self.member)
        response = self.client.post(f"{self.queue_url}{add_b.data['id']}/vote/", {})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
class EventActivityStatusTests(APITestCase):
    """
    Event.sync_activity_status — the automatic ghost_town/rip_attendance/
    party_of_nobody inactivity ladder (live -> ghost_town after
    Event.GHOST_TOWN_AFTER, -> rip_attendance after
    Event.RIP_ATTENDANCE_AFTER, -> party_of_nobody after
    Event.PARTY_OF_NOBODY_AFTER, all measured from the most recent track
    suggestion; resets to live the instant a new one is added).

    Backdates EventSong.added_at / Event.created_at directly via
    .update() (bypassing auto_now_add — same trick already used by
    LocationTimeRestrictedMigrationTests) instead of waiting real time.
    """

    def setUp(self):
        self.host = create_verified_user("host@test.com")
        self.client.force_authenticate(self.host)
        event_resp = self.client.post("/api/v1/events/", {"title": "Test Party"})
        self.event_id = event_resp.data["id"]
        self.event_url = f"/api/v1/events/{self.event_id}/"
        self.queue_url = f"/api/v1/events/{self.event_id}/queue/"

    def _backdate_last_activity(self, delta):
        """Simulate `delta` of real time having passed since the last
        track suggestion — or since the event was created, if no song
        has ever been added yet."""
        moment = timezone.now() - delta
        updated = EventSong.objects.filter(event_id=self.event_id).update(added_at=moment)
        if not updated:
            Event.objects.filter(id=self.event_id).update(created_at=moment)

    def test_freshly_created_event_stays_live(self):
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["status"], "live")

    def test_still_short_of_a_day_stays_live(self):
        self._backdate_last_activity(timedelta(hours=23))
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["status"], "live")

    def test_becomes_ghost_town_after_a_day_of_no_suggestions(self):
        self._backdate_last_activity(timedelta(days=1, minutes=1))
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["status"], "ghost_town")

    def test_becomes_rip_attendance_after_two_days(self):
        self._backdate_last_activity(timedelta(days=2, minutes=1))
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["status"], "rip_attendance")

    def test_becomes_party_of_nobody_after_three_days(self):
        self._backdate_last_activity(timedelta(days=3, minutes=1))
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["status"], "party_of_nobody")

    def test_queue_get_also_triggers_the_sync(self):
        self._backdate_last_activity(timedelta(days=1, minutes=1))
        response = self.client.get(self.queue_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        event = Event.objects.get(id=self.event_id)
        self.assertEqual(event.status, "ghost_town")

    def test_adding_a_track_resets_status_back_to_live(self):
        self._backdate_last_activity(timedelta(days=3, minutes=1))
        self.client.get(self.event_url)  # let it escalate to party_of_nobody
        event = Event.objects.get(id=self.event_id)
        self.assertEqual(event.status, "party_of_nobody")

        response = self.client.post(self.queue_url, {"title": "Song A", "artist": "Artist A"})
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        event.refresh_from_db()
        self.assertEqual(event.status, "live")

    def test_closed_event_is_never_touched_by_the_ladder(self):
        self.client.patch(self.event_url, {"status": "closed"})
        self._backdate_last_activity(timedelta(days=5))
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["status"], "closed")

    def test_canceled_event_is_never_touched_by_the_ladder(self):
        self.client.patch(self.event_url, {"status": "canceled"})
        self._backdate_last_activity(timedelta(days=5))
        response = self.client.get(self.event_url)  # host still has access
        self.assertEqual(response.data["status"], "canceled")

    def test_activity_measured_from_most_recent_song_not_event_creation(self):
        # The event itself is old, but a song was JUST suggested (no
        # backdating on it) — the stale created_at must not matter once
        # there's a real, recent suggestion to measure from instead.
        Event.objects.filter(id=self.event_id).update(
            created_at=timezone.now() - timedelta(days=10)
        )
        self.client.post(self.queue_url, {"title": "Song A", "artist": "Artist A"})
        response = self.client.get(self.event_url)
        self.assertEqual(response.data["status"], "live")