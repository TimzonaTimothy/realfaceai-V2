from django.contrib import admin
from django.utils.html import format_html

from .models import AppRelease
from .versioning import get_policy, invalidate_policy_cache


@admin.register(AppRelease)
class AppReleaseAdmin(admin.ModelAdmin):
    list_display = (
        "platform", "version", "mandatory_badge", "is_published",
        "published_at", "live_state",
    )
    list_filter = ("platform", "is_mandatory", "is_published")
    search_fields = ("version", "release_notes")
    ordering = ("platform", "-published_at")
    readonly_fields = ("created_at", "updated_at")
    actions = ("make_mandatory", "make_optional", "unpublish", "publish")

    fieldsets = (
        (None, {"fields": ("platform", "version", "download_url", "release_notes")}),
        ("Rollout", {
            "fields": ("is_mandatory", "is_published", "published_at"),
            "description": (
                "<b>Mandatory</b> blocks every user on an older version until they "
                "update. Outdated builds also get HTTP 426 from the API, so they "
                "cannot keep using the service. Unticking <b>Published</b> pulls "
                "a release (and lifts its force-update) within about a minute."
            ),
        }),
        ("Timestamps", {"fields": ("created_at", "updated_at"), "classes": ("collapse",)}),
    )

    @admin.display(description="Mandatory", boolean=False, ordering="is_mandatory")
    def mandatory_badge(self, obj):
        if obj.is_mandatory:
            return format_html('<b style="color:#E5322D;">FORCED</b>')
        return "optional"

    @admin.display(description="Status")
    def live_state(self, obj):
        policy = get_policy(obj.platform)
        tags = []
        if policy.latest and policy.latest.version == obj.version:
            tags.append('<span style="color:#0B8A5F;font-weight:600;">latest</span>')
        if policy.min_supported and policy.min_supported.version == obj.version:
            tags.append('<span style="color:#E5322D;font-weight:600;">minimum supported</span>')
        if not tags:
            if not obj.is_published:
                return "hidden"
            return "scheduled" if obj.published_at and obj.published_at > _now() else "—"
        return format_html(" · ".join(tags))

    def _bulk(self, request, queryset, msg, **fields):
        platforms = set(queryset.values_list("platform", flat=True))
        n = queryset.update(**fields)  # .update() skips signals → clear cache ourselves
        for p in platforms:
            invalidate_policy_cache(p)
        self.message_user(request, msg.format(n=n))

    @admin.action(description="Force update to selected releases (mandatory)")
    def make_mandatory(self, request, queryset):
        self._bulk(request, queryset, "{n} release(s) marked mandatory.", is_mandatory=True)

    @admin.action(description="Make selected releases optional")
    def make_optional(self, request, queryset):
        self._bulk(request, queryset, "{n} release(s) marked optional.", is_mandatory=False)

    @admin.action(description="Unpublish selected releases")
    def unpublish(self, request, queryset):
        self._bulk(request, queryset, "{n} release(s) unpublished.", is_published=False)

    @admin.action(description="Publish selected releases")
    def publish(self, request, queryset):
        self._bulk(request, queryset, "{n} release(s) published.", is_published=True)


def _now():
    from django.utils import timezone
    return timezone.now()
