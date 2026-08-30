from unittest.mock import Mock, patch

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

    @patch("api.views.requests.get")
    def test_reports_when_a_track_has_no_preview(self, mock_get):
        deezer_response = Mock()
        deezer_response.json.return_value = {"id": 12345, "preview": ""}
        mock_get.return_value = deezer_response

        response = self.client.get("/api/v1/tracks/12345/preview/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
