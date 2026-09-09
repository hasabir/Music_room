from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest import skipUnless

from django.core.cache import cache
from django.db import connection, connections
from django.test import TransactionTestCase, override_settings
from rest_framework.test import APIClient

from events.models import Song
from user.models import User
from .models import Playlist, PlaylistSong
from .services import add_song_to_playlist


@skipUnless(connection.vendor == 'postgresql', 'Requires real PostgreSQL row locks')
@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PlaylistConcurrencyTests(TransactionTestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(email='playlist-race@example.com', subscription_tier='premium')
        self.playlist = Playlist.objects.create(owner=self.user, title='Concurrent playlist')
        self.url = f'/api/v1/playlists/{self.playlist.pk}/songs/'
        self.songs = [Song.objects.create(title=f'Song {i}', artist='Artist', external_id=f'race-{i}')
                      for i in range(8)]

    def race(self, operations):
        barrier = Barrier(len(operations))

        def run(operation):
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SET lock_timeout = '5s'")
                client = APIClient()
                client.force_authenticate(self.user)
                barrier.wait(timeout=10)
                return operation(client).status_code
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=len(operations)) as executor:
            futures = [executor.submit(run, op) for op in operations]
            return [future.result(timeout=20) for future in futures]

    def add(self, index):
        song = self.songs[index]
        return lambda client: client.post(self.url, {
            'title': song.title, 'artist': song.artist, 'external_id': song.external_id,
        }, format='json')

    def assert_order(self, count):
        rows = list(PlaylistSong.objects.filter(playlist=self.playlist))
        self.assertEqual([row.position for row in rows], list(range(count)))
        self.assertEqual(len({row.song_id for row in rows}), count)

    def test_concurrent_additions_to_empty_playlist_all_succeed(self):
        self.assertEqual(self.race([self.add(i) for i in range(5)]), [201] * 5)
        self.assert_order(5)

    def test_duplicate_concurrent_additions_return_400_not_500(self):
        # Exercise simultaneous first-time catalogue creation too.
        Song.objects.filter(pk=self.songs[0].pk).delete()
        results = self.race([self.add(0) for _ in range(5)])
        self.assertEqual(results.count(201), 1)
        self.assertEqual(results.count(400), 4)
        self.assert_order(1)

    def test_opposite_moves_preserve_order_without_deadlocking(self):
        rows = [add_song_to_playlist(self.playlist, song, self.user) for song in self.songs[:5]]
        results = self.race([
            lambda c: c.post(f'{self.url}{rows[0].pk}/move/', {'new_position': 4}, format='json'),
            lambda c: c.post(f'{self.url}{rows[4].pk}/move/', {'new_position': 0}, format='json'),
        ])
        self.assertEqual(results, [200, 200])
        self.assert_order(5)

    def test_add_move_and_remove_can_race(self):
        rows = [add_song_to_playlist(self.playlist, song, self.user) for song in self.songs[:5]]
        results = self.race([
            self.add(5),
            lambda c: c.delete(f'{self.url}{rows[1].pk}/'),
            lambda c: c.post(f'{self.url}{rows[4].pk}/move/', {'new_position': 0}, format='json'),
        ])
        self.assertEqual(results, [201, 204, 200])
        self.assert_order(5)
        self.assertFalse(PlaylistSong.objects.filter(pk=rows[1].pk).exists())
