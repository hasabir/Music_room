from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("playlists", "0005_playlist_cover_image_playlist_cover_preset_and_more")]

    operations = [
        migrations.AddField(
            model_name="playlistcollaborator",
            name="can_add_songs",
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name="playlistcollaborator",
            name="can_reorder_songs",
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name="playlistcollaborator",
            name="can_manage_collaborators",
            field=models.BooleanField(default=False),
        ),
    ]
