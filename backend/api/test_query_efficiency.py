from django.db import connection
from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from events.models import Event, EventSong, Song
from playlists.models import Playlist, PlaylistSong
from profiles.models import Profile
from user.models import User


@override_settings(
    CACHES={"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}},
)
class ListQueryEfficiencyTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="query-user@example.com", password="x", is_email_verified=True
        )
        Profile.objects.create(user=self.user)
        self.client.force_authenticate(self.user)
        songs = [Song.objects.create(title=f"Song {i}", artist="Artist") for i in range(10)]
        for index in range(30):
            event = Event.objects.create(host=self.user, title=f"Event {index}")
            playlist = Playlist.objects.create(owner=self.user, title=f"Playlist {index}")
            EventSong.objects.bulk_create([
                EventSong(event=event, song=song, added_by=self.user) for song in songs
            ])
            PlaylistSong.objects.bulk_create([
                PlaylistSong(playlist=playlist, song=song, position=position, added_by=self.user)
                for position, song in enumerate(songs)
            ])

    def assert_bounded_queries(self, path, maximum):
        with CaptureQueriesContext(connection) as captured:
            response = self.client.get(path)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 30)
        self.assertLessEqual(
            len(captured), maximum,
            f"{path} executed {len(captured)} queries; list queries must not scale per item",
        )

    def test_event_list_queries_are_bounded(self):
        self.assert_bounded_queries("/api/v1/events/", 15)

    def test_playlist_list_queries_are_bounded(self):
        self.assert_bounded_queries("/api/v1/playlists/", 10)
