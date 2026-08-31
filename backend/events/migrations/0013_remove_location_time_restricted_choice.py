# Removes `location_time_restricted` from vote_permission's choices now
# that every event using it has been converted (see 0012). `choices` on a
# CharField is Python/form-level validation only — Postgres has no CHECK
# constraint backing it — so this is a state-only change with no data
# effect; it must still be a real migration so Django's model state and
# the database's recorded migration history stay in sync with the model.

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('events', '0012_migrate_location_time_restricted_events'),
    ]

    operations = [
        migrations.AlterField(
            model_name='event',
            name='vote_permission',
            field=models.CharField(
                choices=[('everyone', 'Everyone can vote'), ('invited_only', 'Only invited guests can vote')],
                default='everyone',
                max_length=30,
            ),
        ),
    ]
