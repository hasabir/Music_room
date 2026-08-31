from unittest.mock import Mock, patch

import requests
from rest_framework import status
from rest_framework.test import APITestCase

from user.models import User


class TrackPreviewTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="listener@test.com",
            password="TestPass123",
            registration_method="email",
        )
        self.client.force_authenticate(self.user)

    @patch("api.views.requests.get")
    def test_resolves_current_preview_url_for_a_deezer_track(self, mock_get):
        deezer_response = Mock()
        deezer_response.json.return_value = {
            "id": 12345,
            "preview": "https://cdn.example.test/current-preview.mp3",
        }
        mock_get.return_value = deezer_response

        response = self.client.get("/api/v1/tracks/12345/preview/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            response.data["preview_url"],
            "https://cdn.example.test/current-preview.mp3",
        )
        mock_get.assert_called_once_with("https://api.deezer.com/track/12345", timeout=5)

    def test_rejects_non_deezer_external_ids(self):
        response = self.client.get("/api/v1/tracks/not-a-deezer-id/preview/")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_resolves_audius_tracks_to_a_full_stream_url(self):
        response = self.client.get("/api/v1/tracks/audius:AbC123/preview/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            response.data["preview_url"],
            "https://api.audius.co/v1/tracks/AbC123/stream",
        )

    @patch("api.views.requests.get")
    def test_reports_when_a_track_has_no_preview(self, mock_get):
        deezer_response = Mock()
        deezer_response.json.return_value = {"id": 12345, "preview": ""}
        mock_get.return_value = deezer_response

        response = self.client.get("/api/v1/tracks/12345/preview/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class TrackTrendingTests(APITestCase):
    AUDIUS_TRENDING_URL = "https://api.audius.co/v1/tracks/trending"
    DEEZER_CHART_URL = "https://api.deezer.com/chart/0/tracks"

    def setUp(self):
        self.user = User.objects.create_user(
            email="listener@test.com",
            password="TestPass123",
            registration_method="email",
        )
        self.client.force_authenticate(self.user)

    def _mock_response(self, json_data):
        response = Mock()
        response.json.return_value = json_data
        return response

    def _audius_payload(self):
        return {
            "data": [
                {
                    "id": 555,
                    "title": "Audius Hit",
                    "user": {"name": "Indie Artist"},
                    "artwork": {"480x480": "https://cdn.example.test/audius-art.jpg"},
                    "duration": 210,
                    "is_streamable": True,
                },
            ]
        }

    def _deezer_payload(self):
        return {
            "data": [
                {
                    "id": 999,
                    "title": "Chart Topper",
                    "artist": {"name": "Big Artist"},
                    "album": {"cover_medium": "https://cdn.example.test/art.jpg"},
                    "preview": "https://cdn.example.test/preview.mp3",
                    "duration": 200,
                },
            ]
        }

    @patch("api.views.requests.get")
    def test_combines_audius_trending_and_deezer_chart_tracks(self, mock_get):
        def fake_get(url, **kwargs):
            if url == self.AUDIUS_TRENDING_URL:
                return self._mock_response(self._audius_payload())
            if url == self.DEEZER_CHART_URL:
                return self._mock_response(self._deezer_payload())
            raise AssertionError(f"Unexpected URL: {url}")

        mock_get.side_effect = fake_get

        response = self.client.get("/api/v1/tracks/trending/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        # Audius (full-length) results lead, then Deezer previews — same
        # source priority as search.
        self.assertEqual(response.data, [
            {
                "external_id": "audius:555",
                "title": "Audius Hit",
                "artist": "Indie Artist",
                "album_art_url": "https://cdn.example.test/audius-art.jpg",
                "preview_url": "https://api.audius.co/v1/tracks/555/stream",
                "duration_seconds": 210,
                "playback_type": "full",
            },
            {
                "external_id": "999",
                "title": "Chart Topper",
                "artist": "Big Artist",
                "album_art_url": "https://cdn.example.test/art.jpg",
                "preview_url": "https://cdn.example.test/preview.mp3",
                "duration_seconds": 200,
                "playback_type": "preview",
            },
        ])

    @patch("api.views.requests.get")
    def test_deezer_chart_still_returned_when_audius_is_unreachable(self, mock_get):
        def fake_get(url, **kwargs):
            if url == self.AUDIUS_TRENDING_URL:
                raise requests.RequestException("boom")
            return self._mock_response(self._deezer_payload())

        mock_get.side_effect = fake_get

        response = self.client.get("/api/v1/tracks/trending/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["title"], "Chart Topper")

    @patch("api.views.requests.get")
    def test_audius_trending_still_returned_when_deezer_is_unreachable(self, mock_get):
        def fake_get(url, **kwargs):
            if url == self.AUDIUS_TRENDING_URL:
                return self._mock_response(self._audius_payload())
            raise requests.RequestException("boom")

        mock_get.side_effect = fake_get

        response = self.client.get("/api/v1/tracks/trending/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["title"], "Audius Hit")

    @patch("api.views.requests.get")
    def test_reports_a_gateway_error_when_both_sources_are_unreachable(self, mock_get):
        mock_get.side_effect = requests.RequestException("boom")

        response = self.client.get("/api/v1/tracks/trending/")

        self.assertEqual(response.status_code, status.HTTP_502_BAD_GATEWAY)

    def test_requires_authentication(self):
        self.client.force_authenticate(user=None)

        response = self.client.get("/api/v1/tracks/trending/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class TrackSearchTests(APITestCase):
    """`GET /api/v1/tracks/search/?q=...` — default mode, unchanged by the
    `by=artist` refactor: `q` is matched by each source's normal full-text
    track search (title/artist/etc), same as before."""

    AUDIUS_TRACK_SEARCH_URL = "https://api.audius.co/v1/tracks/search"
    DEEZER_TRACK_SEARCH_URL = "https://api.deezer.com/search"

    def setUp(self):
        self.user = User.objects.create_user(
            email="listener@test.com",
            password="TestPass123",
            registration_method="email",
        )
        self.client.force_authenticate(self.user)

    def _mock_response(self, json_data):
        response = Mock()
        response.json.return_value = json_data
        return response

    @patch("api.views.requests.get")
    def test_combines_audius_and_deezer_keyword_matches(self, mock_get):
        def fake_get(url, **kwargs):
            if url == self.AUDIUS_TRACK_SEARCH_URL:
                return self._mock_response({
                    "data": [{
                        "id": 555, "title": "Deep Cut",
                        "user": {"name": "Indie Artist"},
                        "artwork": {"480x480": "https://cdn.example.test/audius-art.jpg"},
                        "duration": 210, "is_streamable": True,
                    }]
                })
            if url == self.DEEZER_TRACK_SEARCH_URL:
                return self._mock_response({
                    "data": [{
                        "id": 999, "title": "Signature Hit",
                        "artist": {"name": "Big Artist"},
                        "album": {"cover_medium": "https://cdn.example.test/art.jpg"},
                        "preview": "https://cdn.example.test/preview.mp3", "duration": 200,
                    }]
                })
            raise AssertionError(f"Unexpected URL: {url}")

        mock_get.side_effect = fake_get

        response = self.client.get("/api/v1/tracks/search/?q=hit")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 2)
        self.assertEqual(response.data[0]["playback_type"], "full")
        self.assertEqual(response.data[1]["playback_type"], "preview")

    def test_requires_q(self):
        response = self.client.get("/api/v1/tracks/search/")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class TrackSearchByArtistTests(APITestCase):
    """`GET /api/v1/tracks/search/?q=...&by=artist` — an artist-name
    lookup (find the best-matching artist, then list their tracks) rather
    than a keyword match against every field."""

    AUDIUS_USER_SEARCH_URL = "https://api.audius.co/v1/users/search"
    AUDIUS_USER_TRACKS_URL = "https://api.audius.co/v1/users/42/tracks"
    AUDIUS_TRACK_SEARCH_URL = "https://api.audius.co/v1/tracks/search"
    DEEZER_ARTIST_SEARCH_URL = "https://api.deezer.com/search/artist"
    DEEZER_ARTIST_TOP_URL = "https://api.deezer.com/artist/7/top"
    DEEZER_TRACK_SEARCH_URL = "https://api.deezer.com/search"

    def setUp(self):
        self.user = User.objects.create_user(
            email="listener@test.com",
            password="TestPass123",
            registration_method="email",
        )
        self.client.force_authenticate(self.user)

    def _mock_response(self, json_data):
        response = Mock()
        response.json.return_value = json_data
        return response

    def _audius_user_payload(self):
        return {"data": [{"id": 42, "name": "Indie Artist", "handle": "indieartist"}]}

    def _audius_tracks_payload(self):
        return {
            "data": [
                {
                    "id": 555,
                    "title": "Deep Cut",
                    "user": {"name": "Indie Artist"},
                    "artwork": {"480x480": "https://cdn.example.test/audius-art.jpg"},
                    "duration": 210,
                    "is_streamable": True,
                },
            ]
        }

    def _deezer_artist_payload(self):
        return {"data": [{"id": 7, "name": "Big Artist"}]}

    def _deezer_top_payload(self):
        return {
            "data": [
                {
                    "id": 999,
                    "title": "Signature Hit",
                    "artist": {"name": "Big Artist"},
                    "album": {"cover_medium": "https://cdn.example.test/art.jpg"},
                    "preview": "https://cdn.example.test/preview.mp3",
                    "duration": 200,
                },
            ]
        }

    @patch("api.views.requests.get")
    def test_by_artist_returns_the_matched_artists_tracks(self, mock_get):
        def fake_get(url, **kwargs):
            if url == self.AUDIUS_USER_SEARCH_URL:
                return self._mock_response(self._audius_user_payload())
            if url == self.AUDIUS_USER_TRACKS_URL:
                return self._mock_response(self._audius_tracks_payload())
            if url == self.DEEZER_ARTIST_SEARCH_URL:
                return self._mock_response(self._deezer_artist_payload())
            if url == self.DEEZER_ARTIST_TOP_URL:
                return self._mock_response(self._deezer_top_payload())
            raise AssertionError(f"Unexpected URL: {url}")

        mock_get.side_effect = fake_get

        response = self.client.get("/api/v1/tracks/search/?q=big+artist&by=artist")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [
            {
                "external_id": "audius:555",
                "title": "Deep Cut",
                "artist": "Indie Artist",
                "album_art_url": "https://cdn.example.test/audius-art.jpg",
                "preview_url": "https://api.audius.co/v1/tracks/555/stream",
                "duration_seconds": 210,
                "playback_type": "full",
            },
            {
                "external_id": "999",
                "title": "Signature Hit",
                "artist": "Big Artist",
                "album_art_url": "https://cdn.example.test/art.jpg",
                "preview_url": "https://cdn.example.test/preview.mp3",
                "duration_seconds": 200,
                "playback_type": "preview",
            },
        ])
        # Never the plain keyword-search endpoints — artist mode looks the
        # artist up first instead.
        called_urls = {call.args[0] for call in mock_get.call_args_list}
        self.assertNotIn(self.AUDIUS_TRACK_SEARCH_URL, called_urls)
        self.assertNotIn(self.DEEZER_TRACK_SEARCH_URL, called_urls)

    @patch("api.views.requests.get")
    def test_by_artist_is_empty_when_no_artist_matches(self, mock_get):
        def fake_get(url, **kwargs):
            if url == self.AUDIUS_USER_SEARCH_URL:
                return self._mock_response({"data": []})
            if url == self.DEEZER_ARTIST_SEARCH_URL:
                return self._mock_response({"data": []})
            raise AssertionError(f"Unexpected URL: {url}")

        mock_get.side_effect = fake_get

        response = self.client.get("/api/v1/tracks/search/?q=nobody&by=artist")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data, [])

    @patch("api.views.requests.get")
    def test_by_artist_falls_back_to_audius_when_deezer_artist_lookup_fails(self, mock_get):
        def fake_get(url, **kwargs):
            if url == self.AUDIUS_USER_SEARCH_URL:
                return self._mock_response(self._audius_user_payload())
            if url == self.AUDIUS_USER_TRACKS_URL:
                return self._mock_response(self._audius_tracks_payload())
            if url == self.DEEZER_ARTIST_SEARCH_URL:
                raise requests.RequestException("boom")
            raise AssertionError(f"Unexpected URL: {url}")

        mock_get.side_effect = fake_get

        response = self.client.get("/api/v1/tracks/search/?q=indie+artist&by=artist")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["title"], "Deep Cut")

    def test_by_artist_still_requires_q(self):
        response = self.client.get("/api/v1/tracks/search/?by=artist")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
