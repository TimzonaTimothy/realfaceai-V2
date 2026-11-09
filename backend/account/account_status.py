"""
account/account_status.py

Suspend / freeze / reactivate accounts.

    active    — normal use.
    frozen    — read-only. The user can sign in and view their dashboard,
                usage and billing history, but every write (stream, generate,
                buy credits, upload payment proof …) is refused with
                403 {"code": "account_frozen"}.
    suspended — locked out. Sign-in, token refresh and every authenticated
                API call are refused with 403 {"code": "account_suspended"}.

Both restrictions take effect on the user's very next request — the check
runs inside JWT authentication (account/authentication.py), so there's no
need to revoke tokens. A live stream stops on its next 10-second heartbeat
because the 403 body carries `"stop": true`, which every desktop build
already honours.

A restriction can be temporary (`expires_at`); it's lifted lazily the next
time the account is seen after that moment, and the lift is audited like any
other change.

ALWAYS change status through `change_account_status()` so the audit log,
notification email and in-memory object stay consistent.
"""

from __future__ import annotations

import logging
import threading
from datetime import datetime
from typing import Optional

from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.db import transaction
from django.template.loader import render_to_string
from django.utils import timezone
from rest_framework import status as http_status
from rest_framework.exceptions import APIException

from .models import Account, AccountStatusLog

log = logging.getLogger(__name__)

ACTIVE = Account.STATUS_ACTIVE
FROZEN = Account.STATUS_FROZEN
SUSPENDED = Account.STATUS_SUSPENDED
VALID_STATUSES = {ACTIVE, FROZEN, SUSPENDED}

CODE_SUSPENDED = "account_suspended"
CODE_FROZEN = "account_frozen"


# ── Errors returned to the client ────────────────────────────────────────────

class AccountRestricted(APIException):
    """
    403 with a structured body the desktop app understands:

        {
          "error":  "<human message>",   # what existing screens already display
          "detail": "<human message>",
          "code":   "account_suspended" | "account_frozen",
          "stop":   true,                # ends a live stream on next heartbeat
          "account_status": {status, reason, expires_at, changed_at, support_email}
        }
    """
    status_code = http_status.HTTP_403_FORBIDDEN
    default_code = "account_restricted"

    def __init__(self, account: Account, code: str):
        message = restriction_message(account, code)
        super().__init__(detail=message, code=code)
        # Bypass DRF's ErrorDetail coercion so booleans / nulls survive.
        self.detail = restriction_body(account, code, message)


class AccountSuspended(AccountRestricted):
    def __init__(self, account: Account):
        super().__init__(account, CODE_SUSPENDED)


class AccountFrozen(AccountRestricted):
    def __init__(self, account: Account):
        super().__init__(account, CODE_FROZEN)


def _fmt_dt(value: Optional[datetime]) -> Optional[str]:
    return value.isoformat() if value else None


def _human_until(value: Optional[datetime]) -> str:
    if not value:
        return ""
    return timezone.localtime(value).strftime("%b %d, %Y %H:%M %Z")


def status_payload(account: Account) -> dict:
    return {
        "status": account.account_status,
        "reason": account.status_reason or "",
        "expires_at": _fmt_dt(account.status_expires_at),
        "changed_at": _fmt_dt(account.status_changed_at),
        "support_email": getattr(settings, "SUPPORT_EMAIL", ""),
    }


def restriction_message(account: Account, code: str) -> str:
    support = getattr(settings, "SUPPORT_EMAIL", "support")
    if code == CODE_SUSPENDED:
        parts = ["Your account has been suspended."]
    else:
        parts = ["Your account is frozen, so this action isn't available. You can still view your account."]
    if account.status_reason:
        parts.append(f"Reason: {account.status_reason}.")
    if account.status_expires_at:
        parts.append(f"This ends on {_human_until(account.status_expires_at)}.")
    parts.append(f"If you think this is a mistake, contact {support}.")
    return " ".join(parts)


def restriction_body(account: Account, code: str, message: Optional[str] = None) -> dict:
    message = message or restriction_message(account, code)
    return {
        "error": message,
        "detail": message,
        "code": code,
        "stop": True,
        "account_status": status_payload(account),
    }


# ── Reading status ───────────────────────────────────────────────────────────

def lift_if_expired(account: Account) -> bool:
    """Restore an account whose temporary restriction has passed. Returns True if lifted."""
    if (
        account.account_status != ACTIVE
        and account.status_expires_at is not None
        and account.status_expires_at <= timezone.now()
    ):
        result = change_account_status(
            account, ACTIVE,
            reason="", note="Restriction expired.",
            source=AccountStatusLog.SOURCE_EXPIRY,
            require_expired=True,
        )
        return result is not None
    return False


def effective_status(account: Account) -> str:
    """The account's status right now (lifting an expired restriction first)."""
    lift_if_expired(account)
    return account.account_status


# ── Changing status ──────────────────────────────────────────────────────────

class StatusChangeError(ValueError):
    pass


def change_account_status(
    account: Account,
    new_status: str,
    *,
    reason: str = "",
    note: str = "",
    expires_at: Optional[datetime] = None,
    actor: Optional[Account] = None,
    source: str = AccountStatusLog.SOURCE_SYSTEM,
    notify: bool = True,
    require_expired: bool = False,
) -> Optional[AccountStatusLog]:
    """
    Atomically set an account's status, write an audit row, and (optionally)
    email the user. Returns the log row, or None when nothing changed.

    `account` is updated in place so callers can keep using it.
    """
    if new_status not in VALID_STATUSES:
        raise StatusChangeError(f"Unknown status '{new_status}'. Use one of: {', '.join(sorted(VALID_STATUSES))}.")

    reason = (reason or "").strip()[:500]
    note = (note or "").strip()

    if new_status == ACTIVE:
        reason, expires_at = "", None
    elif expires_at is not None and expires_at <= timezone.now():
        raise StatusChangeError("The end time must be in the future.")

    with transaction.atomic():
        locked = Account.objects.select_for_update().get(pk=account.pk)

        if require_expired and not (
            locked.account_status != ACTIVE
            and locked.status_expires_at is not None
            and locked.status_expires_at <= timezone.now()
        ):
            # Someone else already lifted / changed it — just resync.
            _sync(account, locked)
            return None

        unchanged = (
            locked.account_status == new_status
            and (locked.status_reason or "") == reason
            and locked.status_expires_at == expires_at
        )
        if unchanged:
            _sync(account, locked)
            return None

        previous = locked.account_status
        now = timezone.now()
        locked.account_status = new_status
        locked.status_reason = reason
        locked.status_note = note
        locked.status_expires_at = expires_at
        locked.status_changed_at = now
        locked.status_changed_by = actor
        locked.save(update_fields=[
            "account_status", "status_reason", "status_note",
            "status_expires_at", "status_changed_at", "status_changed_by",
        ])

        entry = AccountStatusLog.objects.create(
            account=locked,
            from_status=previous,
            to_status=new_status,
            reason=reason,
            note=note,
            expires_at=expires_at,
            actor=actor,
            source=source,
        )

        if notify and previous != new_status:
            transaction.on_commit(lambda: _notify_async(locked.pk, previous))

    _sync(account, locked)
    log.info(
        "Account %s status %s -> %s (source=%s, actor=%s)",
        account.email, previous, new_status, source, getattr(actor, "email", None),
    )
    return entry


def _sync(target: Account, source: Account) -> None:
    for field in (
        "account_status", "status_reason", "status_note",
        "status_expires_at", "status_changed_at", "status_changed_by_id",
    ):
        setattr(target, field, getattr(source, field))


# ── Notification email ───────────────────────────────────────────────────────

_SUBJECTS = {
    SUSPENDED: "Your RealFaceAI account has been suspended",
    FROZEN: "Your RealFaceAI account has been frozen",
    ACTIVE: "Your RealFaceAI account is active again",
}


def _notify_async(account_id: int, previous: str) -> None:
    # SMTP can be slow on shared hosting — never hold the request on it.
    threading.Thread(target=_send_status_email, args=(account_id, previous), daemon=True).start()


def _send_status_email(account_id: int, previous: str) -> None:
    try:
        account = Account.objects.get(pk=account_id)
        html = render_to_string("emails/account_status.html", {
            "site_url": getattr(settings, "SITE_URL", ""),
            "email": account.email,
            "status": account.account_status,
            "previous": previous,
            "reason": account.status_reason,
            "until": _human_until(account.status_expires_at),
            "support_email": getattr(settings, "SUPPORT_EMAIL", ""),
        })
        msg = EmailMultiAlternatives(
            subject=_SUBJECTS.get(account.account_status, "Your RealFaceAI account"),
            body="This email needs an HTML-capable mail client.",
            from_email=settings.DEFAULT_FROM_EMAIL,
            to=[account.email],
            reply_to=[getattr(settings, "SUPPORT_EMAIL", settings.DEFAULT_FROM_EMAIL)],
        )
        msg.attach_alternative(html, "text/html")
        msg.send(fail_silently=False)
    except Exception:  # never let email failure affect the status change
        log.exception("Failed to send account status email for account %s", account_id)
