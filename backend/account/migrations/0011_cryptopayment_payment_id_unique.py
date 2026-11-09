from django.db import migrations, models
import account.models


class Migration(migrations.Migration):

    dependencies = [
        ('account', '0010_cryptopayment_payment_id_backfill'),
    ]

    operations = [
        migrations.AlterField(
            model_name='cryptopayment',
            name='payment_id',
            field=models.CharField(
                max_length=20,
                unique=True,
                editable=False,
                db_index=True,
                default=account.models.generate_payment_id,
                help_text='Random public payment reference (e.g. PYM-4X7B2QQK).',
            ),
        ),
    ]