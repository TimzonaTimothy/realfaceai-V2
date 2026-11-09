"""
account/authentication.py

JWT authentication that also enforces account status. It's configured as the
project-wide DEFAULT_AUTHENTICATION_CLASSES, so every DRF view is covered
without touching each view's permission_classes.

simplejwt already loads the user from the database on every request, so the
status check costs no extra query.
"""

from rest_framework.permissions import SAFE_METHODS
from rest_framework_simplejwt.authentication import JWTAuthentication

from .account_status import (
    FROZEN,
    SUSPENDED,
    AccountFrozen,
    AccountSuspended,
    effective_status,
)

# Writes a FROZEN account may still make. Keep this list short: a freeze is
# meant to stop anything that moves money or consumes credits.
FROZEN_WRITE_ALLOWLIST = frozenset({
    "/api/v1/auth/desktop/change-password/",  # securing the account is always allowed
})


class AccountStatusJWTAuthentication(JWTAuthentication):
    def authenticate(self, request):
        result = super().authenticate(request)
        if result is None:
            return None

        user, _token = result
        current = effective_status(user)

        if current == SUSPENDED:
            raise AccountSuspended(user)

        if (
            current == FROZEN
            and request.method not in SAFE_METHODS
            and request.path not in FROZEN_WRITE_ALLOWLIST
        ):
            raise AccountFrozen(user)

        return result
