from django.db import models
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver
from django.utils import timezone

from .versioning import (
    PLATFORM_CHOICES,
    invalidate_policy_cache,
    parse_version,
    validate_version,
)


class AppRelease(models.Model):
    """
    One published desktop build for one platform. Managed from Django admin.

    To ship a release:
      1. Upload the installer to the website's download page.
      2. Admin → App releases → Add: platform, version, download URL, notes.
      3. Tick "Mandatory" to force everyone below this version to update.

    Users see it within a few minutes: the app re-checks periodically, and
    the API starts rejecting outdated builds (HTTP 426) as soon as a
    mandatory release is live.
    """

    platform = models.CharField(max_length=16, choices=PLATFORM_CHOICES, db_index=True)
    version = models.CharField(
        max_length=32,
        validators=[validate_version],
        help_text="Semantic version of the build, e.g. 1.2.0. Must match "
                  "kCurrentVersion in the desktop app for that build.",
    )
    download_url = models.URLField(
        max_length=500,
        help_text="Page the app opens in the browser, e.g. "
                  "https://realfaceai.app/download?platform=windows",
    )
    release_notes = models.TextField(blank=True, help_text="Shown to users in the update prompt.")
    is_mandatory = models.BooleanField(
        "Mandatory (force update)",
        default=False,
        help_text="Everyone on an OLDER version is blocked from using the app "
                  "until they install this one (or newer).",
    )
    is_published = models.BooleanField(
        default=True,
        help_text="Untick to hide this release from the app — use it to stage "
                  "a release or pull a bad one.",
    )
    published_at = models.DateTimeField(
        default=timezone.now,
        help_text="The release goes live at this time. Set it in the future "
                  "to schedule a release.",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["platform", "-published_at"]
        constraints = [
            models.UniqueConstraint(fields=["platform", "version"], name="uniq_app_release_platform_version"),
        ]
        verbose_name = "App release"
        verbose_name_plural = "App releases"

    def __str__(self):
        flag = " (mandatory)" if self.is_mandatory else ""
        return f"{self.get_platform_display()} {self.version}{flag}"

    @property
    def version_tuple(self):
        return parse_version(self.version)

    def save(self, *args, **kwargs):
        self.version = (self.version or "").strip().lstrip("vV")
        super().save(*args, **kwargs)


@receiver(post_save, sender=AppRelease)
@receiver(post_delete, sender=AppRelease)
def _invalidate_release_policy(sender, instance, **kwargs):
    invalidate_policy_cache(instance.platform)
