from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("profiles", "0007_profile_location_latitude_profile_location_longitude")]

    operations = [
        migrations.AddField(
            model_name="profile",
            name="location_from_gps",
            field=models.BooleanField(default=False),
        ),
    ]
