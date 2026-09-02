# Adds SocialAccount.email (the linked Google account's own email,
# independent of User.email) and makes `user` unique so a user can have at
# most one linked Google account (reject, not replace — see DECISIONS.md).
#
# Backfill: under the old GoogleLinkView, a link was only ever allowed when
# the Google email already matched the platform email, and every
# GoogleLoginView-created account's User.email *is* the Google email it
# signed up with — so `user.email` is a lossless backfill for every
# pre-existing row.

from django.db import migrations, models
import django.db.models.deletion


def populate_social_account_email(apps, schema_editor):
    SocialAccount = apps.get_model("user", "SocialAccount")
    for social_account in SocialAccount.objects.select_related("user").iterator():
        social_account.email = social_account.user.email
        social_account.save(update_fields=["email"])


class Migration(migrations.Migration):
    dependencies = [("user", "0003_user_username")]

    operations = [
        migrations.AddField(
            model_name="socialaccount",
            name="email",
            field=models.EmailField(blank=True, default="", max_length=254),
        ),
        migrations.RunPython(populate_social_account_email, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="socialaccount",
            name="email",
            field=models.EmailField(max_length=254),
        ),
        migrations.AlterField(
            model_name="socialaccount",
            name="user",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name="social_accounts",
                to="user.user",
                unique=True,
            ),
        ),
    ]
