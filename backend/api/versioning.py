"""
api/versioning.py

Single source of truth for "which desktop build is current, and which builds
are still allowed to talk to the API".

Concepts
--------
* An ``AppRelease`` row is one published build for one platform.
* The *latest* release for a platform is the highest published version.
* The *minimum supported* version for a platform is the highest published
  release that is marked ``is_mandatory``. Any client below it is forced to
  update — the app shows a blocking screen and the API answers 426.

  Example (windows):
      1.0.5  optional
      1.1.0  MANDATORY   <- minimum supported
      1.2.0  optional    <- latest

      client 1.0.5 -> force update (download page serves 1.2.0)
      client 1.1.0 -> optional update banner
      client 1.2.0 -> up to date

The policy is read on every API request by ``AppVersionMiddleware``, so it is
cached per process for ``APP_UPDATE_POLICY_CACHE_SECONDS`` (default 60s) and
invalidated in-process whenever a release is saved or deleted. With several
gunicorn workers, other workers pick the change up when their cache expires.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional, Tuple

from django.conf import settings
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.utils import timezone

PLATFORM_WINDOWS = "windows"
PLATFORM_MACOS = "macos"
PLATFORM_CHOICES = [
    (PLATFORM_WINDOWS, "Windows"),
    (PLATFORM_MACOS, "macOS"),
]
SUPPORTED_PLATFORMS = {p for p, _ in PLATFORM_CHOICES}

# Aliases clients might send.
_PLATFORM_ALIASES = {
    "windows": PLATFORM_WINDOWS,
    "win": PLATFORM_WINDOWS,
    "win32": PLATFORM_WINDOWS,
    "macos": PLATFORM_MACOS,
    "mac": PLATFORM_MACOS,
    "darwin": PLATFORM_MACOS,
    "osx": PLATFORM_MACOS,
}

VersionTuple = Tuple[int, int, int, int]

# "1.2.3", "v1.2", "1.2.3.4", "1.2.3+45", "1.2.3-beta.1"
# Pre-release / build suffixes are ignored for ordering purposes.
_VERSION_RE = re.compile(r"^\s*[vV]?(\d{1,6}(?:\.\d{1,6}){0,3})(?:[-+][0-9A-Za-z.\-+]*)?\s*$")

_CACHE_KEY = "app_update_policy:{platform}"


# ── Version helpers ──────────────────────────────────────────────────────────

def parse_version(value) -> Optional[VersionTuple]:
    """Parse a version string into a comparable 4-tuple, or None if invalid."""
    if value is None:
        return None
    match = _VERSION_RE.match(str(value))
    if not match:
        return None
    parts = [int(p) for p in match.group(1).split(".")]
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts)  # type: ignore[return-value]


def validate_version(value) -> None:
    """Model-field validator."""
    if parse_version(value) is None:
        raise ValidationError(
            "Enter a version like 1.2.3 (up to four numeric parts).",
            code="invalid_version",
        )


def normalize_platform(value) -> Optional[str]:
    if not value:
        return None
    return _PLATFORM_ALIASES.get(str(value).strip().lower())


# ── Policy ───────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class ReleaseInfo:
    version: str
    version_tuple: VersionTuple
    download_url: str
    release_notes: str
    is_mandatory: bool
    published_at: Optional[str]


@dataclass(frozen=True)
class PlatformPolicy:
    platform: str
    latest: Optional[ReleaseInfo]
    min_supported: Optional[ReleaseInfo]  # newest mandatory release

    @property
    def min_supported_version(self) -> Optional[str]:
        return self.min_supported.version if self.min_supported else None

    def is_forced(self, client: Optional[VersionTuple]) -> bool:
        """True when a client at `client` must update before using the app."""
        if client is None or self.min_supported is None:
            return False
        return client < self.min_supported.version_tuple

    def has_update(self, client: Optional[VersionTuple]) -> bool:
        if self.latest is None:
            return False
        if client is None:
            return True
        return client < self.latest.version_tuple


def _cache_seconds() -> int:
    return int(getattr(settings, "APP_UPDATE_POLICY_CACHE_SECONDS", 60))


def _build_policy(platform: str) -> PlatformPolicy:
    from .models import AppRelease  # local import: models import this module

    rows = (
        AppRelease.objects
        .filter(platform=platform, is_published=True, published_at__lte=timezone.now())
        .only("version", "download_url", "release_notes", "is_mandatory", "published_at")
    )

    latest: Optional[ReleaseInfo] = None
    min_supported: Optional[ReleaseInfo] = None
    for row in rows:
        vt = parse_version(row.version)
        if vt is None:
            continue  # defensive: validator should prevent this
        info = ReleaseInfo(
            version=row.version,
            version_tuple=vt,
            download_url=row.download_url,
            release_notes=row.release_notes or "",
            is_mandatory=row.is_mandatory,
            published_at=row.published_at.isoformat() if row.published_at else None,
        )
        if latest is None or vt > latest.version_tuple:
            latest = info
        if row.is_mandatory and (min_supported is None or vt > min_supported.version_tuple):
            min_supported = info

    return PlatformPolicy(platform=platform, latest=latest, min_supported=min_supported)


def get_policy(platform: str) -> PlatformPolicy:
    key = _CACHE_KEY.format(platform=platform)
    policy = cache.get(key)
    if policy is None:
        policy = _build_policy(platform)
        cache.set(key, policy, _cache_seconds())
    return policy


def invalidate_policy_cache(platform: Optional[str] = None) -> None:
    platforms = [platform] if platform else list(SUPPORTED_PLATFORMS)
    cache.delete_many([_CACHE_KEY.format(platform=p) for p in platforms])


# ── Response payloads ────────────────────────────────────────────────────────

def update_required_message(client_version: Optional[str], policy: PlatformPolicy) -> str:
    target = policy.latest.version if policy.latest else policy.min_supported_version
    if client_version:
        return (
            f"RealFaceAI {client_version} is no longer supported. "
            f"Please update to version {target} to continue."
        )
    return f"This version of RealFaceAI is no longer supported. Please update to version {target} to continue."


def build_version_payload(
    platform: str,
    client_version: Optional[str],
    policy: Optional[PlatformPolicy] = None,
) -> dict:
    """
    Response body for GET /api/v1/app/latest-version/.

    Keeps every field the 1.0.x desktop builds already parse
    (version, download_url, release_notes, mandatory, platform) and adds the
    fields newer builds use to decide between "optional banner" and
    "blocking update screen".
    """
    policy = policy or get_policy(platform)
    client = parse_version(client_version)
    latest = policy.latest

    forced = policy.is_forced(client)
    if client is not None:
        mandatory = forced
    else:
        # Legacy builds don't tell us their version. They only display the
        # notice when `version` is newer than their own, and make it
        # undismissable when `mandatory` is true — so report whether any
        # mandatory release exists at all.
        mandatory = policy.min_supported is not None

    return {
        # ── fields understood by every build ─────────────────────────────
        "platform": platform,
        "version": latest.version,
        "download_url": latest.download_url,
        "release_notes": latest.release_notes,
        "mandatory": mandatory,
        # ── fields for builds that send their version ────────────────────
        "published_at": latest.published_at,
        "current_version": client_version if client is not None else None,
        "min_supported_version": policy.min_supported_version,
        "update_available": policy.has_update(client),
        "force_update": forced,
        "message": update_required_message(client_version, policy) if forced else "",
    }
