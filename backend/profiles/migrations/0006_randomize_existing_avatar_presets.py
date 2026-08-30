import random

from django.db import migrations


def randomize_avatar_presets(apps, schema_editor):
    """
    The previous migration's `AddField` backfilled every pre-existing row
    with the *same* preset (Django evaluates a callable default once for
    the whole batch, not per row) — this gives each one an independent
    random pick instead, matching what actually happens for a row created
    from now on via the model field's default.
    """
    Profile = apps.get_model("profiles", "Profile")
    preset_ids = [str(n) for n in range(1, 12)]
    for profile in Profile.objects.filter(avatar_type="preset"):
        profile.avatar_preset_id = random.choice(preset_ids)
        profile.save(update_fields=["avatar_preset_id"])


class Migration(migrations.Migration):

    dependencies = [
        ("profiles", "0005_profile_avatar_external_url_profile_avatar_preset_id_and_more"),
    ]

    operations = [
        migrations.RunPython(randomize_avatar_presets, migrations.RunPython.noop),
    ]
