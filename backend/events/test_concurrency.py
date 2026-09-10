# events/concurrency_tests.py
"""
Real cross-connection concurrency tests for the FREE-tier suggestion/vote
limits (see events/services.py, docs/SUBSCRIPTION_BONUS.md).

Deliberately NOT in events/tests.py, and deliberately NOT APITestCase:
APITestCase (and plain TestCase) wraps each test in one outer transaction
on a single DB connection, which would hide the exact race these tests
exist to catch — every thread would just be fighting over the same
already-open transaction rather than exercising genuine Postgres
row-locking across separate connections. TransactionTestCase runs each
test against real, separately-committed state and lets each thread open
its own real connection, which is what's actually required to reproduce
(and prove protection against) this class of race.
"""
import threading

from django.db import connection
from django.test import TransactionTestCase
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from user.models import User
from .models import DailyParticipation, Event, EventSong, Song, Vote
from .services import FREE_SUGGESTION_LIMIT, FREE_VOTE_LIMIT


class SuggestionLimitConcurrencyTests(TransactionTestCase):
    def setUp(self):
        self.host = User.objects.create_user(
            email="conc_host@test.com", password="x", registration_method="email"
        )
        self.user = User.objects.create_user(
            email="conc_free@test.com", password="x", registration_method="email"
        )
        self.event = Event.objects.create(host=self.host, title="Concurrency Party", visibility="public")
        self.event.members.create(member=self.user)
        DailyParticipation.objects.create(
            user=self.user, date=timezone.localdate(), suggestion_count=FREE_SUGGESTION_LIMIT - 1
        )

    def test_two_concurrent_suggestions_at_the_boundary_only_one_succeeds(self):
        """Free user sitting at 9/10. Fire 5 truly concurrent suggestions
        for 5 different new songs — exactly one may succeed."""
        results = []

        def attempt(i, barrier):
            try:
                barrier.wait()
                client = APIClient()
                client.force_authenticate(self.user)
                response = client.post(
                    f"/api/v1/events/{self.event.id}/queue/",
                    {"title": f"Concurrent Song {i}", "artist": "Artist"},
                    format="json",
                )
                results.append(response.status_code)
            finally:
                connection.close()

        thread_count = 5
        barrier = threading.Barrier(thread_count)
        threads = [threading.Thread(target=attempt, args=(i, barrier)) for i in range(thread_count)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(results.count(status.HTTP_201_CREATED), 1)
        self.assertEqual(results.count(status.HTTP_403_FORBIDDEN), thread_count - 1)
        self.assertEqual(
            DailyParticipation.objects.get(user=self.user, date=timezone.localdate()).suggestion_count,
            FREE_SUGGESTION_LIMIT,
        )


class VoteLimitConcurrencyTests(TransactionTestCase):
    def setUp(self):
        self.host = User.objects.create_user(
            email="conc_host2@test.com", password="x", registration_method="email"
        )
        self.user = User.objects.create_user(
            email="conc_free2@test.com", password="x", registration_method="email"
        )
        self.event = Event.objects.create(host=self.host, title="Concurrency Party 2", visibility="public")
        self.songs = []
        for i in range(FREE_VOTE_LIMIT + 5):
            song = Song.objects.create(title=f"Concurrency Song {i}", artist="Artist")
            self.songs.append(EventSong.objects.create(event=self.event, song=song, added_by=self.host))
        # One below the cap, pre-seeded directly.
        for event_song in self.songs[: FREE_VOTE_LIMIT - 1]:
            Vote.objects.create(event_song=event_song, voter=self.user)

    def test_two_concurrent_votes_at_the_boundary_only_one_succeeds(self):
        """Free user sitting at 19/20 distinct votes. Fire 5 truly
        concurrent votes on 5 different not-yet-voted songs — exactly
        one may succeed."""
        candidates = self.songs[FREE_VOTE_LIMIT - 1:]
        results = []

        def attempt(event_song, barrier):
            try:
                barrier.wait()
                client = APIClient()
                client.force_authenticate(self.user)
                response = client.post(
                    f"/api/v1/events/{self.event.id}/queue/{event_song.id}/vote/",
                    {},
                    format="json",
                )
                results.append(response.status_code)
            finally:
                connection.close()

        barrier = threading.Barrier(len(candidates))
        threads = [threading.Thread(target=attempt, args=(es, barrier)) for es in candidates]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(results.count(status.HTTP_201_CREATED), 1)
        self.assertEqual(results.count(status.HTTP_403_FORBIDDEN), len(candidates) - 1)
        self.assertEqual(
            Vote.objects.filter(voter=self.user, created_at__date=timezone.localdate()).count(),
            FREE_VOTE_LIMIT,
        )
