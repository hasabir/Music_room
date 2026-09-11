from unittest.mock import patch

from django.test import SimpleTestCase

from .models import Profile
from .serializers import ProfileSerializer


class GPSLocationTests(SimpleTestCase):
    def test_manual_location_is_rejected(self):
        serializer = ProfileSerializer(Profile(location=""), data={"location": "Paris"}, partial=True)
        self.assertFalse(serializer.is_valid())
        self.assertIn("location", serializer.errors)

    def test_coordinates_require_valid_pair(self):
        for data in (
            {"location_latitude": 20},
            {"location_latitude": 91, "location_longitude": 0},
            {"location_latitude": 0, "location_longitude": 181},
        ):
            with self.subTest(data=data):
                serializer = ProfileSerializer(Profile(), data=data, partial=True)
                self.assertFalse(serializer.is_valid())

    def test_exact_gps_coordinates_are_preserved(self):
        profile = Profile(location="")
        serializer = ProfileSerializer(profile, data={
            "location": "GPS location",
            "location_latitude": 33.57312345,
            "location_longitude": -7.58987654,
        }, partial=True)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        with patch.object(Profile, "save"):
            serializer.save()
        self.assertEqual(profile.location_latitude, 33.57312345)
        self.assertEqual(profile.location_longitude, -7.58987654)
        self.assertTrue(profile.location_from_gps)

    def test_unchanged_label_preserves_gps(self):
        profile = Profile(location="Saved", location_from_gps=True)
        serializer = ProfileSerializer(profile, data={"location": "Saved"}, partial=True)
        self.assertTrue(serializer.is_valid(), serializer.errors)
