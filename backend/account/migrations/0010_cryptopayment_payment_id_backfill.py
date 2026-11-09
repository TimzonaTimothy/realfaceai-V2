from django.db import migrations
import secrets


def generate_payment_id():
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "PYM-" + "".join(secrets.choice(alphabet) for _ in range(8))


def backfill_payment_ids(apps, schema_editor):
    CryptoPayment = apps.get_model('account', 'CryptoPayment')
    existing = set()
    for payment in CryptoPayment.objects.all().iterator():
        code = generate_payment_id()
        while code in existing:
            code = generate_payment_id()
        existing.add(code)
        payment.payment_id = code
        payment.save(update_fields=['payment_id'])


class Migration(migrations.Migration):

    dependencies = [
        ('account', '0009_cryptopayment_payment_id_add'),
    ]

    operations = [
        migrations.RunPython(backfill_payment_ids, migrations.RunPython.noop),
    ]