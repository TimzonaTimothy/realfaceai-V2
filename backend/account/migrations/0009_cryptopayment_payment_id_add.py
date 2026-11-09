from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('account', '0008_auto_20260907_1016'),
    ]

    operations = [
        migrations.AddField(
            model_name='cryptopayment',
            name='payment_id',
            field=models.CharField(max_length=20, null=True, editable=False),
        ),
    ]