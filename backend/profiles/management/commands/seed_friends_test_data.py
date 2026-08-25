from django.core.management.base import BaseCommand
from django.db import transaction

from user.models import User
from profiles.models import Friendship, Profile

TEST_PASSWORD = "TestPass123!"

# The account to sign in as when testing the Friends / Pending Requests
# screens. It ends up with: accepted friends, requests it received that
# are still pending, requests it sent that are still pending, and one
# rejected request.
MAIN_EMAIL = "friends.test@example.com"

ACCEPTED_FRIENDS = [
    {"email": "amara.friend1@example.com", "first_name": "Amara", "last_name": "Diallo",
     "display_name": "Amara D.", "bio": "House & Afrobeat DJ.", "location": "Lagos, Nigeria",
     "favorite_genres": ["house", "afrobeat"]},
    {"email": "ben.friend2@example.com", "first_name": "Ben", "last_name": "Okafor",
     "display_name": "Ben O.", "bio": "Vinyl collector, jazz head.", "location": "London, UK",
     "favorite_genres": ["jazz", "soul"]},
    {"email": "chloe.friend3@example.com", "first_name": "Chloe", "last_name": "Martins",
     "display_name": "Chloe M.", "bio": "Synthwave producer.", "location": "Berlin, Germany",
     "favorite_genres": ["electronic", "indie"]},
]

# Sent a request TO the main user; still pending their response.
INCOMING_PENDING = [
    {"email": "dara.incoming1@example.com", "first_name": "Dara", "last_name": "Kim",
     "display_name": "Dara K.", "bio": "K-pop stan account.", "location": "Seoul, South Korea",
     "favorite_genres": ["kpop", "pop"]},
    {"email": "evan.incoming2@example.com", "first_name": "Evan", "last_name": "Torres",
     "display_name": "Evan T.", "bio": "Metalhead, occasional folk.", "location": "Mexico City, Mexico",
     "favorite_genres": ["metal", "folk"]},
]

# The main user sent these; still pending the other side's response.
OUTGOING_PENDING = [
    {"email": "farah.outgoing1@example.com", "first_name": "Farah", "last_name": "Haddad",
     "display_name": "Farah H.", "bio": "Classical pianist.", "location": "Beirut, Lebanon",
     "favorite_genres": ["classical", "soundtrack"]},
    {"email": "gus.outgoing2@example.com", "first_name": "Gus", "last_name": "Larsen",
     "display_name": "Gus L.", "bio": "Techno all night.", "location": "Copenhagen, Denmark",
     "favorite_genres": ["techno"]},
]

# One rejected request, to cover that status in the UI too.
REJECTED = [
    {"email": "hana.rejected1@example.com", "first_name": "Hana", "last_name": "Suzuki",
     "display_name": "Hana S.", "bio": "Rarely uses this app.", "location": "Osaka, Japan",
     "favorite_genres": ["rnb"]},
]


class Command(BaseCommand):
    help = (
        "Seeds a main test account plus a set of counterpart users covering "
        "accepted friends, incoming pending requests, outgoing pending "
        "requests, and a rejected request — for exercising the Friends / "
        "Pending Requests screens end to end. Safe to run multiple times."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--email",
            default=MAIN_EMAIL,
            help=f"Email of the main test account to sign in as (default: {MAIN_EMAIL}).",
        )

    def handle(self, *args, **options):
        main_email = options["email"]

        with transaction.atomic():
            main_user = self._get_or_create_user(
                main_email, "Main", "Tester",
                display_name="Main Tester", bio="Seeded account for testing friends.",
                location="Test City", favorite_genres=["pop", "rock"],
            )

            for data in ACCEPTED_FRIENDS:
                other = self._get_or_create_user(**data)
                self._get_or_create_friendship(main_user, other, "accepted")

            for data in INCOMING_PENDING:
                other = self._get_or_create_user(**data)
                self._get_or_create_friendship(other, main_user, "pending")

            for data in OUTGOING_PENDING:
                other = self._get_or_create_user(**data)
                self._get_or_create_friendship(main_user, other, "pending")

            for data in REJECTED:
                other = self._get_or_create_user(**data)
                self._get_or_create_friendship(main_user, other, "rejected")

        self.stdout.write(self.style.SUCCESS(
            f"Seeded friends test data. Sign in as {main_email} / {TEST_PASSWORD}"
        ))

    def _get_or_create_user(self, email, first_name, last_name, *, display_name, bio, location, favorite_genres):
        user, created = User.objects.get_or_create(
            email=email,
            defaults={
                "first_name": first_name,
                "last_name": last_name,
                "is_email_verified": True,
            },
        )
        if created:
            user.set_password(TEST_PASSWORD)
            user.save(update_fields=["password"])

        Profile.objects.update_or_create(
            user=user,
            defaults={
                "display_name": display_name,
                "bio": bio,
                "location": location,
                "favorite_genres": favorite_genres,
            },
        )
        return user

    def _get_or_create_friendship(self, sender, receiver, status):
        friendship, created = Friendship.objects.get_or_create(
            sender=sender,
            receiver=receiver,
            defaults={"status": status},
        )
        if not created and friendship.status != status:
            friendship.status = status
            friendship.save(update_fields=["status", "updated_at"])
        return friendship
