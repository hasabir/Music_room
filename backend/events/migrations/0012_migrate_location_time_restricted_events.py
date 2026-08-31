# Data migration: convert existing events using the old combined
# `location_time_restricted` vote_permission value into the new
# composable-restriction shape.
#
# `location_time_restricted` bundled "invited-only voting" with "must be
# at the venue, during the window" as one inseparable option. Splitting it
# into two independent toggles means that old value no longer means
# anything on its own — every event that had it needs an explicit,
# equivalent replacement, not just a default. `invited_only` (rather than
# `everyone`) is chosen deliberately to preserve the "restricted" spirit
# of the original setting: these events were never meant to be open to
# just anyone, and defaulting them to `everyone` would silently loosen
# access for existing hosts. Both restriction toggles are set True, and
# the existing venue/time field values are carried over unchanged — no
# host had a reason to lose data they already configured.
from django.db import migrations


def migrate_forward(apps, schema_editor):
    Event = apps.get_model("events", "Event")
    Event.objects.filter(vote_permission="location_time_restricted").update(
        vote_permission="invited_only",
        time_restriction_enabled=True,
        location_restriction_enabled=True,
    )


def migrate_backward(apps, schema_editor):
    # Not reversible in a lossless way: multiple pre-migration states
    # (e.g. `invited_only` + only one restriction enabled) can't be told
    # apart from a genuine former `location_time_restricted` event once
    # forward-migrated. Restoring the exact old value for every row this
    # migration touched would require having recorded which rows those
    # were — which it deliberately doesn't, since RunPython.noop is the
    # honest representation of "this direction can't be undone cleanly"
    # rather than silently guessing.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('events', '0011_event_restriction_toggles'),
    ]

    operations = [
        migrations.RunPython(migrate_forward, migrate_backward),
    ]
