import json
import secrets
from pathlib import Path

from django.contrib.auth.hashers import make_password
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from events.models import Event, EventMembership, EventSong, Song
from playlists.models import Playlist, PlaylistMembership, PlaylistSong
from profiles.models import Profile
from user.models import User


class Command(BaseCommand):
    help = "Seed the isolated load-test database and write Locust credentials."

    def add_arguments(self, parser):
        parser.add_argument("--users", type=int, default=100)
        parser.add_argument("--events", type=int, default=60)
        parser.add_argument("--playlists", type=int, default=60)
        parser.add_argument("--songs", type=int, default=120)
        parser.add_argument("--output", required=True)

    @transaction.atomic
    def handle(self, *args, **options):
        counts = {name: options[name] for name in ("users", "events", "playlists", "songs")}
        if any(value < 1 for value in counts.values()):
            raise CommandError("All seed counts must be positive")
        if User.objects.filter(email__startswith="load-user-").exists():
            raise CommandError("Load-test users already exist; use a fresh load-test volume")

        password = secrets.token_urlsafe(18)
        encoded_password = make_password(password)
        users = User.objects.bulk_create([
            User(
                email=f"load-user-{index:04d}@example.invalid",
                username=f"load_user_{index:04d}",
                password=encoded_password,
                is_email_verified=True,
                registration_method="email",
            )
            for index in range(counts["users"])
        ])
        Profile.objects.bulk_create([
            Profile(user=user, display_name=f"Load User {index:04d}", favorite_genres=["pop", "rock"])
            for index, user in enumerate(users)
        ])

        songs = Song.objects.bulk_create([
            Song(
                external_id=f"load-song-{index:04d}",
                title=f"Load Song {index:04d}",
                artist=f"Load Artist {index % 20:02d}",
                duration_seconds=180 + index % 120,
            )
            for index in range(counts["songs"])
        ])
        events = Event.objects.bulk_create([
            Event(
                host=users[index % len(users)],
                title=f"Load Event {index:04d}",
                description="Synthetic capacity-test event",
                visibility="public" if index % 2 == 0 else "private",
            )
            for index in range(counts["events"])
        ])
        playlists = Playlist.objects.bulk_create([
            Playlist(
                owner=users[index % len(users)],
                title=f"Load Playlist {index:04d}",
                description="Synthetic capacity-test playlist",
                visibility="public" if index % 2 == 0 else "private",
            )
            for index in range(counts["playlists"])
        ])

        EventSong.objects.bulk_create([
            EventSong(event=event, song=songs[(event_index * 10 + offset) % len(songs)], added_by=event.host)
            for event_index, event in enumerate(events)
            for offset in range(min(10, len(songs)))
        ])
        PlaylistSong.objects.bulk_create([
            PlaylistSong(
                playlist=playlist,
                song=songs[(playlist_index * 10 + offset) % len(songs)],
                position=offset,
                added_by=playlist.owner,
            )
            for playlist_index, playlist in enumerate(playlists)
            for offset in range(min(10, len(songs)))
        ])

        public_events = [event for event in events if event.visibility == "public"]
        public_playlists = [playlist for playlist in playlists if playlist.visibility == "public"]
        EventMembership.objects.bulk_create([
            EventMembership(event=event, member=users[(index + 1) % len(users)])
            for index, event in enumerate(public_events)
            if users[(index + 1) % len(users)] != event.host
        ])
        # Every synthetic user can participate in one shared public event,
        # giving the contention and WebSocket workloads a deterministic target.
        # Compared by id, not by object equality, and verified by a re-count
        # afterward — bulk_create's ignore_conflicts silently drops rows that
        # violate the (event, member) unique constraint, so a stale/aliased
        # host reference here would silently under-seed the very membership
        # set the write/WebSocket load scripts depend on to run at all.
        shared_event = public_events[0]
        EventMembership.objects.bulk_create([
            EventMembership(event=shared_event, member=user)
            for user in users
            if user.id != shared_event.host_id
        ], ignore_conflicts=True)
        member_count = EventMembership.objects.filter(event=shared_event).count()
        if member_count != len(users) - 1:
            raise CommandError(
                f"Shared event {shared_event.id} has {member_count} members, "
                f"expected {len(users) - 1}; write/WebSocket load scripts need "
                f"every synthetic user to be a member."
            )
        PlaylistMembership.objects.bulk_create([
            PlaylistMembership(playlist=playlist, member=users[(index + 1) % len(users)])
            for index, playlist in enumerate(public_playlists)
            if users[(index + 1) % len(users)] != playlist.owner
        ])

        output = Path(options["output"])
        output.write_text(
            json.dumps([{"email": user.email, "password": password} for user in users], indent=2),
            encoding="utf-8",
        )
        self.stdout.write(self.style.SUCCESS(
            f"Seeded {len(users)} users, {len(events)} events, "
            f"{len(playlists)} playlists and {len(songs)} songs; credentials written to {output}"
        ))
