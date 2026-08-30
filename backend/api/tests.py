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
