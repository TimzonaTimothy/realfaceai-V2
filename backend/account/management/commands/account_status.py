"""
Suspend, freeze or reactivate an account from the shell.

    python manage.py account_status user@example.com                     # show status + history
    python manage.py account_status user@example.com suspend --reason "Chargeback under review"
    python manage.py account_status user@example.com freeze --hours 72 --reason "Payment check"
    python manage.py account_status user@example.com activate
    python manage.py account_status user@example.com suspend --no-notify --note "internal only"
"""

from datetime import timedelta

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from account.account_status import StatusChangeError, change_account_status, effective_status
from account.models import Account, AccountStatusLog

_ALIASES = {
    "suspend": Account.STATUS_SUSPENDED,
    "suspended": Account.STATUS_SUSPENDED,
    "freeze": Account.STATUS_FROZEN,
    "frozen": Account.STATUS_FROZEN,
    "activate": Account.STATUS_ACTIVE,
    "active": Account.STATUS_ACTIVE,
    "reactivate": Account.STATUS_ACTIVE,
    "unfreeze": Account.STATUS_ACTIVE,
    "unsuspend": Account.STATUS_ACTIVE,
}


class Command(BaseCommand):
    help = "Show or change an account's status (active / frozen / suspended)."

    def add_arguments(self, parser):
        parser.add_argument("email")
        parser.add_argument("action", nargs="?", choices=sorted(_ALIASES), help="Omit to just show the status.")
        parser.add_argument("--reason", default="", help="Shown to the user.")
        parser.add_argument("--note", default="", help="Internal only.")
        parser.add_argument("--hours", type=float, help="Lift automatically after this many hours.")
        parser.add_argument("--no-notify", action="store_true", help="Don't email the user.")

    def handle(self, *args, **opts):
        account = Account.objects.filter(email__iexact=opts["email"].strip()).first()
        if account is None:
            raise CommandError(f"No account with email {opts['email']}")

        if opts["action"]:
            expires_at = None
            if opts["hours"]:
                if opts["hours"] <= 0:
                    raise CommandError("--hours must be positive")
                expires_at = timezone.now() + timedelta(hours=opts["hours"])
            try:
                entry = change_account_status(
                    account, _ALIASES[opts["action"]],
                    reason=opts["reason"], note=opts["note"], expires_at=expires_at,
                    source=AccountStatusLog.SOURCE_COMMAND, notify=not opts["no_notify"],
                )
            except StatusChangeError as e:
                raise CommandError(str(e))
            self.stdout.write(self.style.SUCCESS("Updated.") if entry else "No change (already in that state).")

        effective_status(account)
        self.stdout.write(f"\n{account.email}: {account.get_account_status_display()}")
        if account.status_reason:
            self.stdout.write(f"  reason:  {account.status_reason}")
        if account.status_expires_at:
            self.stdout.write(f"  until:   {timezone.localtime(account.status_expires_at):%Y-%m-%d %H:%M %Z}")
        history = account.status_history.select_related("actor")[:10]
        if history:
            self.stdout.write("\nRecent changes:")
            for h in history:
                who = h.actor.email if h.actor else h.get_source_display()
                self.stdout.write(f"  {h.created_at:%Y-%m-%d %H:%M}  {h.from_status} → {h.to_status}  ({who}) {h.reason}")
