from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from account.models import UserProfile, DepositTransaction, UserDepositAddress

User = get_user_model()

class Command(BaseCommand):
    help = "Check credit and deposit balances for a user or all users."

    def add_arguments(self, parser):
        parser.add_argument("--email", type=str, help="Filter by user email")

    def handle(self, *args, **options):
        email = options.get("email")

        if email:
            try:
                user = User.objects.get(email=email)
                profiles = UserProfile.objects.filter(user=user)
            except User.DoesNotExist:
                self.stderr.write(f"No user found with email: {email}")
                return
        else:
            profiles = UserProfile.objects.select_related("user").order_by("-credits")

        for p in profiles:
            self.stdout.write(f"\n{'='*50}")
            self.stdout.write(f"Email   : {p.user.email}")
            self.stdout.write(f"Credits : {p.credits}")
            self.stdout.write(f"Plan    : {p.plan}")

            addrs = UserDepositAddress.objects.filter(user=p.user)
            for a in addrs:
                self.stdout.write(f"Wallet  : {a.network} {a.token} → {a.address}")

            txs = DepositTransaction.objects.filter(user=p.user).order_by("-detected_at")[:5]
            if txs:
                self.stdout.write("Last deposits:")
                for tx in txs:
                    self.stdout.write(
                        f"  {tx.detected_at:%Y-%m-%d %H:%M} | {tx.network} | "
                        f"{tx.amount} {tx.token} | {tx.status} | +{tx.credits_added} credits"
                    )

# # All users
# python manage.py check_balance

# # One specific user
# python manage.py check_balance --email user@example.com