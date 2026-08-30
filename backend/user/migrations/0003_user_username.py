# Generated manually to give every existing account a unique public username.

import re

from django.core.validators import RegexValidator
from django.db import migrations, models


def populate_usernames(apps, schema_editor):
    User = apps.get_model("user", "User")
    used = set()

    for user in User.objects.order_by("id").iterator():
        base = re.sub(r"[^a-z0-9_.]", "", user.email.split("@", 1)[0].lower())
        base = (base or "musicroom")[:24]
        if len(base) < 3:
            base = f"{base}user"[:24]
        candidate = base
        suffix = 1
        while candidate.lower() in used:
            suffix_text = str(suffix)
            candidate = f"{base[:30 - len(suffix_text)]}{suffix_text}"
            suffix += 1
        user.username = candidate
        user.save(update_fields=["username"])
        used.add(candidate.lower())


class Migration(migrations.Migration):
    dependencies = [("user", "0002_actionlog_metadata")]

    operations = [
        migrations.AddField(
            model_name="user",
            name="username",
            field=models.CharField(blank=True, max_length=30, null=True),
        ),
        migrations.RunPython(populate_usernames, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="user",
            name="username",
            field=models.CharField(
                max_length=30,
                unique=True,
                validators=[
                    RegexValidator(
                        "^[A-Za-z0-9_.]{3,30}$",
                        "Username must be 3–30 letters, numbers, dots, or underscores.",
                    ),
                ],
            ),
        ),
    ]
