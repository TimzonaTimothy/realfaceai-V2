# from django.contrib import admin, messages
# from django.contrib.auth.admin import UserAdmin
# from django.db import transaction
# from django.utils import timezone

# from .models import *
from django.contrib import admin, messages
from django.contrib.auth.admin import UserAdmin
from django.db import transaction
from django.utils import timezone
from django.utils.html import format_html

from .models import *

# ─── Account ────────────────────────────────────────────────────────────────
from datetime import timedelta

from django import forms
from django.contrib.admin.helpers import ACTION_CHECKBOX_NAME
from django.template.response import TemplateResponse

from .account_status import StatusChangeError, change_account_status


_STATUS_COLORS = {
    Account.STATUS_ACTIVE: "#0B8A5F",
    Account.STATUS_FROZEN: "#0B6FC2",
    Account.STATUS_SUSPENDED: "#E5322D",
}


class AccountStatusActionForm(forms.Form):
    """Intermediate form for the bulk suspend / freeze actions."""
    DURATIONS = [
        ("", "Indefinitely (until reactivated)"),
        ("24", "24 hours"),
        ("72", "3 days"),
        ("168", "7 days"),
        ("720", "30 days"),
    ]
    reason = forms.CharField(
        max_length=500, required=False,
        widget=forms.TextInput(attrs={"size": 70}),
        help_text="Shown to the user in the app and the email. Keep it factual.",
    )
    duration = forms.ChoiceField(choices=DURATIONS, required=False)
    note = forms.CharField(
        required=False, widget=forms.Textarea(attrs={"rows": 3, "cols": 70}),
        help_text="Internal only.",
    )
    notify = forms.BooleanField(required=False, initial=True, label="Email the user")


class AccountStatusLogInline(admin.TabularInline):
    model = AccountStatusLog
    fk_name = "account"
    extra = 0
    can_delete = False
    ordering = ("-created_at",)
    fields = ("created_at", "from_status", "to_status", "reason", "expires_at", "source", "actor", "note")
    readonly_fields = fields
    verbose_name_plural = "Status history"

    def has_add_permission(self, request, obj=None):
        return False


class AccountAdmin(UserAdmin):
    list_display = ('email', 'date_joined', 'status_badge', 'is_active', 'is_admin')
    list_display_links = ('email',)
    ordering = ('-date_joined',)

    fieldsets = (
        (None, {'fields': ('email', 'password')}),
        ('Account status', {
            'fields': (
                'account_status', 'status_reason', 'status_expires_at', 'status_note',
                'status_changed_at', 'status_changed_by',
            ),
            'description': (
                '<b>Frozen</b>: can sign in and view, but can\'t stream, generate or pay. '
                '<b>Suspended</b>: fully locked out. Both take effect on the user\'s next '
                'request and stop a live stream within ~10 seconds. Changes here are '
                'audited and the user is emailed.'
            ),
        }),
        ('Permissions', {'fields': ('is_admin', 'is_staff', 'is_active', 'is_superadmin', 'is_superuser', 'groups', 'user_permissions')}),
        ('Important dates', {'fields': ('last_login', 'date_joined')}),
    )
    readonly_fields = ('status_changed_at', 'status_changed_by')

    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('email', 'password1', 'password2'),
        }),
    )

    filter_horizontal = ('groups', 'user_permissions')
    list_filter = ('account_status', 'date_joined', 'is_active')
    list_per_page = 25
    search_fields = ('email',)
    inlines = [AccountStatusLogInline]
    actions = ['suspend_accounts', 'freeze_accounts', 'reactivate_accounts']

    _STATUS_FIELDS = ('account_status', 'status_reason', 'status_expires_at', 'status_note')

    @admin.display(description='Status', ordering='account_status')
    def status_badge(self, obj):
        color = _STATUS_COLORS.get(obj.account_status, '#687085')
        label = obj.get_account_status_display().split(' (')[0]
        suffix = ''
        if obj.status_expires_at and obj.account_status != Account.STATUS_ACTIVE:
            suffix = f' · until {timezone.localtime(obj.status_expires_at):%b %d %H:%M}'
        return format_html('<b style="color:{};">{}</b>{}', color, label, suffix)

    # Route status edits on the change form through the service so they're
    # validated, audited and emailed exactly like the bulk actions.
    def save_model(self, request, obj, form, change):
        status_changed = change and any(f in form.changed_data for f in self._STATUS_FIELDS)
        if not status_changed:
            return super().save_model(request, obj, form, change)

        wanted = {f: getattr(obj, f) for f in self._STATUS_FIELDS}
        current = Account.objects.get(pk=obj.pk)
        for f in self._STATUS_FIELDS:  # save everything else first, status untouched
            setattr(obj, f, getattr(current, f))
        super().save_model(request, obj, form, change)

        if obj.pk == request.user.pk:
            self.message_user(request, "You can't change your own account status.", messages.ERROR)
            return
        try:
            entry = change_account_status(
                obj, wanted['account_status'],
                reason=wanted['status_reason'], note=wanted['status_note'],
                expires_at=wanted['status_expires_at'],
                actor=request.user, source=AccountStatusLog.SOURCE_ADMIN,
            )
        except StatusChangeError as e:
            self.message_user(request, f"Status not changed: {e}", messages.ERROR)
            return
        if entry:
            self.message_user(request, f"{obj.email} is now {obj.get_account_status_display()}.", messages.SUCCESS)

    # ── Bulk actions ────────────────────────────────────────────────────────
    def _status_action(self, request, queryset, new_status, title):
        protected = queryset.filter(pk=request.user.pk)
        if not request.user.is_superuser:
            protected = protected | queryset.filter(is_staff=True) | queryset.filter(is_superuser=True)
        targets = queryset.exclude(pk__in=protected.values('pk'))

        if new_status == Account.STATUS_ACTIVE or 'apply' in request.POST:
            form = AccountStatusActionForm(request.POST if 'apply' in request.POST else None)
            if new_status != Account.STATUS_ACTIVE and not form.is_valid():
                return self._render_status_form(request, queryset, form, title)
            data = form.cleaned_data if form.is_bound and form.is_valid() else {}
            expires_at = None
            if data.get('duration'):
                expires_at = timezone.now() + timedelta(hours=int(data['duration']))

            changed = 0
            for account in targets:
                try:
                    if change_account_status(
                        account, new_status,
                        reason=data.get('reason', ''), note=data.get('note', ''),
                        expires_at=expires_at, actor=request.user,
                        source=AccountStatusLog.SOURCE_ADMIN,
                        notify=data.get('notify', True),
                    ):
                        changed += 1
                except StatusChangeError as e:
                    self.message_user(request, f"{account.email}: {e}", messages.ERROR)

            self.message_user(request, f"{changed} account(s) set to {new_status}.", messages.SUCCESS)
            skipped = protected.distinct().count()
            if skipped:
                self.message_user(
                    request,
                    f"Skipped {skipped} account(s): your own account and staff accounts "
                    f"(only a superuser can restrict staff).",
                    messages.WARNING,
                )
            return None

        return self._render_status_form(request, queryset, AccountStatusActionForm(), title)

    def _render_status_form(self, request, queryset, form, title):
        context = {
            **self.admin_site.each_context(request),
            'title': title,
            'opts': self.model._meta,
            'queryset': queryset,
            'form': form,
            'action': request.POST.get('action'),
            'action_checkbox_name': ACTION_CHECKBOX_NAME,
        }
        return TemplateResponse(request, 'admin/account/account_status_action.html', context)

    @admin.action(description='⛔ Suspend selected accounts (lock out)')
    def suspend_accounts(self, request, queryset):
        return self._status_action(request, queryset, Account.STATUS_SUSPENDED, 'Suspend accounts')

    @admin.action(description='❄ Freeze selected accounts (read-only)')
    def freeze_accounts(self, request, queryset):
        return self._status_action(request, queryset, Account.STATUS_FROZEN, 'Freeze accounts')

    @admin.action(description='✓ Reactivate selected accounts')
    def reactivate_accounts(self, request, queryset):
        return self._status_action(request, queryset, Account.STATUS_ACTIVE, 'Reactivate accounts')

admin.site.register(Account, AccountAdmin)


@admin.register(AccountStatusLog)
class AccountStatusLogAdmin(admin.ModelAdmin):
    list_display = ('created_at', 'account', 'from_status', 'to_status', 'reason', 'expires_at', 'source', 'actor')
    list_filter = ('to_status', 'source', 'created_at')
    search_fields = ('account__email', 'reason', 'note', 'actor__email')
    date_hierarchy = 'created_at'
    readonly_fields = [f.name for f in AccountStatusLog._meta.fields]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


# ─── UserProfile ────────────────────────────────────────────────────────────
@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'credits', 'plan')
    search_fields = ('user__email',)
    list_filter = ('plan',)
    raw_id_fields = ('user',)



# ─── Usage Logs ─────────────────────────────────────────────────────────────
@admin.register(UsageLog)
class UsageLogAdmin(admin.ModelAdmin):
    list_display = ('user', 'endpoint', 'model_used', 'credits_used', 'timestamp')
    list_filter = ('endpoint', 'timestamp')
    search_fields = ('user__email', 'model_used')
    raw_id_fields = ('user',)
    readonly_fields = ('timestamp',)
    date_hierarchy = 'timestamp'


# ─── Crypto Payments ────────────────────────────────────────────────────────
def _confirm_payments_action(modeladmin, request, queryset):
    """
    Admin action: confirm selected waiting/confirming payments,
    credit users atomically, and send Resend email notifications.
    """
    from .payment_views import _credit_user_atomic, _get_user_profile

    confirmed = 0
    skipped   = 0
    errors    = 0

    eligible = queryset.filter(
        status__in=[CryptoPayment.STATUS_WAITING, CryptoPayment.STATUS_CONFIRMING]
    ).select_related("user")

    for payment in eligible:
        try:
            success, new_balance = _credit_user_atomic(payment)
            if success:
                confirmed += 1
                modeladmin.message_user(
                    request,
                    f"✓ Confirmed #{payment.id} for {payment.user.email} "
                    f"— {payment.credits_to_add:,} credits added (new balance: {new_balance:,.0f})",
                    messages.SUCCESS,
                )
            else:
                skipped += 1
                modeladmin.message_user(
                    request,
                    f"⚠ Payment #{payment.id} ({payment.user.email}) was already confirmed — skipped.",
                    messages.WARNING,
                )
        except Exception as e:
            errors += 1
            modeladmin.message_user(
                request,
                f"✗ Error confirming #{payment.id} ({payment.user.email}): {e}",
                messages.ERROR,
            )

    already_confirmed = queryset.filter(status=CryptoPayment.STATUS_CONFIRMED).count()
    if already_confirmed:
        modeladmin.message_user(
            request,
            f"{already_confirmed} payment(s) were already confirmed and were skipped.",
            messages.WARNING,
        )

_confirm_payments_action.short_description = "✓ Confirm selected payments & credit users"

from django.contrib import admin
from django.db.models import Count
from django.shortcuts import get_object_or_404
from django.urls import path, reverse
from django.utils.html import format_html
from .models import PaymentProof


# ─── Payment proofs: shared helpers ─────────────────────────────────────────
def _proof_image_url(proof):
    """Admin-only URL that streams the proof (local copy first, Cloudinary fallback)."""
    return reverse('admin:account_paymentproof_image', args=[proof.pk])


def _proof_preview_html(proof, max_height=200):
    if not proof.has_image:
        return format_html(
            '<span style="color:#E5322D;font-weight:600;">No image stored</span>'
            '<br><small>Upload failed before the fix — ask the user to re-upload.</small>'
        )
    url = _proof_image_url(proof)
    return format_html(
        '<a href="{}" target="_blank">'
        '<img src="{}" style="max-height:{}px; max-width:400px; '
        'border-radius:8px; border:1px solid #ccc;" />'
        '</a>',
        url, url, max_height,
    )


def _storage_badge(proof):
    if proof.proof_image:
        return format_html('<span style="color:green;font-weight:600;">Local + Cloudinary</span>')
    if proof.local_image:
        note = 'Cloudinary mirror failed' if proof.upload_status == PaymentProof.STATUS_FAILED else 'Cloudinary mirror pending'
        return format_html('<span style="color:#0B6FC2;font-weight:600;">Local</span> <small>({})</small>', note)
    return format_html('<span style="color:#E5322D;font-weight:600;">Missing</span>')


# ─── Crypto Payments ────────────────────────────────────────────────────────
class PaymentProofInline(admin.StackedInline):
    model        = PaymentProof
    extra        = 0
    readonly_fields = ('proof_image_preview', 'storage', 'tx_hash', 'notes', 'original_filename', 'submitted_at')
    fields       = ('proof_image_preview', 'storage', 'tx_hash', 'notes', 'original_filename', 'submitted_at')
    can_delete   = False
    # Newest submission first — a payment can have a whole history of re-uploads.
    ordering     = ('-submitted_at',)

    def has_add_permission(self, request, obj=None):
        return False

    def proof_image_preview(self, obj):
        return _proof_preview_html(obj, 200)
    proof_image_preview.short_description = 'Receipt / Screenshot'

    def storage(self, obj):
        return _storage_badge(obj)
    storage.short_description = 'Stored'


@admin.register(CryptoPayment)
class CryptoPaymentAdmin(admin.ModelAdmin):
    list_display = (
        'payment_id', 'user', 'pack_label', 'amount_usd', 'credits_to_add',
        'currency', 'wallet_short', 'status', 'has_proof', 'created_at', 'confirmed_at',
    )
    list_filter = ('status', 'gateway', 'currency', 'created_at')
    search_fields = ('payment_id', 'user__email', 'pack_label', 'wallet_address')
    raw_id_fields = ('user',)
    readonly_fields = ('payment_id', 'created_at', 'confirmed_at')
    date_hierarchy = 'created_at'
    actions = [_confirm_payments_action]
    inlines = [PaymentProofInline]

    def get_queryset(self, request):
        return (
            super().get_queryset(request)
            .select_related('user')
            .annotate(proof_count=Count('proofs'))
        )

    def wallet_short(self, obj):
        a = obj.wallet_address or ''
        return f'{a[:6]}…{a[-4:]}' if len(a) > 12 else (a or '—')
    wallet_short.short_description = 'Wallet'

    def has_proof(self, obj):
        count = getattr(obj, 'proof_count', 0)
        color = 'green' if count else '#999'
        label = f'{count} submitted' if count else 'None'
        return format_html('<span style="color:{}; font-weight:600;">{}</span>', color, label)
    has_proof.short_description = 'Proof'
    has_proof.admin_order_field = 'proof_count'


def _retry_cloudinary_action(modeladmin, request, queryset):
    from .proof_views import push_proof_to_cloudinary
    ok = failed = 0
    for proof in queryset:
        if push_proof_to_cloudinary(proof.pk):
            ok += 1
        else:
            failed += 1
    modeladmin.message_user(
        request,
        f'Cloudinary mirror: {ok} succeeded, {failed} failed '
        f'(failed ones are still viewable from the local copy).',
        messages.SUCCESS if not failed else messages.WARNING,
    )

_retry_cloudinary_action.short_description = 'Retry Cloudinary upload for selected proofs'


@admin.register(PaymentProof)
class PaymentProofAdmin(admin.ModelAdmin):
    list_display  = ('payment_ref', 'user_email', 'tx_hash_short', 'submitted_at',
                     'payment_status', 'storage', 'proof_image_preview')
    list_filter   = ('submitted_at', 'payment__status', 'upload_status')
    search_fields = ('payment__payment_id', 'payment__user__email', 'tx_hash')
    readonly_fields = ('proof_image_preview', 'storage', 'upload_error', 'original_filename', 'submitted_at')
    exclude       = ('proof_image', 'local_image', 'idempotency_key')
    ordering      = ('-submitted_at',)
    actions       = [_retry_cloudinary_action]

    def get_urls(self):
        custom = [
            path('<int:proof_id>/image/', self.admin_site.admin_view(self.image_view),
                 name='account_paymentproof_image'),
        ]
        return custom + super().get_urls()

    def image_view(self, request, proof_id):
        from .proof_views import open_proof_image
        proof = get_object_or_404(PaymentProof, pk=proof_id)
        return open_proof_image(proof)

    def payment_ref(self, obj):
        return obj.payment.payment_id
    payment_ref.short_description = 'Payment'

    def user_email(self, obj):
        return obj.payment.user.email
    user_email.short_description = 'User'

    def tx_hash_short(self, obj):
        return obj.tx_hash[:20] + '…' if len(obj.tx_hash) > 20 else obj.tx_hash or '—'
    tx_hash_short.short_description = 'TX Hash'

    def payment_status(self, obj):
        status = obj.payment.status
        colors = {'confirmed': 'green', 'waiting': 'orange', 'failed': 'red'}
        color  = colors.get(status, 'gray')
        return format_html('<span style="color:{}; font-weight:600;">{}</span>', color, status.upper())
    payment_status.short_description = 'Status'

    def storage(self, obj):
        return _storage_badge(obj)
    storage.short_description = 'Stored'

    def proof_image_preview(self, obj):
        return _proof_preview_html(obj, 180)
    proof_image_preview.short_description = 'Preview'


# ─── Crypto Wallets ─────────────────────────────────────────────────────────
@admin.register(CryptoWallet)
class CryptoWalletAdmin(admin.ModelAdmin):
    list_display  = ('id', 'network', 'label', 'address_short', 'is_active', 'created_at')
    list_filter   = ('network', 'is_active')
    search_fields = ('network', 'label', 'address')
    list_editable = ('is_active',)
    ordering      = ('network', 'id')

    fieldsets = (
        (None, {
            'fields': ('network', 'label', 'address', 'is_active'),
        }),
        ('Internal notes', {
            'fields': ('notes',),
            'classes': ('collapse',),
        }),
    )

    def address_short(self, obj):
        addr = obj.address
        if len(addr) > 20:
            return addr[:10] + '…' + addr[-8:]
        return addr
    address_short.short_description = 'Address'


# ─── Fiat Currencies ────────────────────────────────────────────────────────
@admin.register(FiatCurrency)
class FiatCurrencyAdmin(admin.ModelAdmin):
    list_display  = ('flag', 'currency_id', 'label', 'is_active', 'sort_order')
    list_editable = ('is_active', 'sort_order')
    ordering      = ('sort_order', 'id')
    search_fields = ('currency_id', 'label')




@admin.register(UserDepositAddress)
class UserDepositAddressAdmin(admin.ModelAdmin):
    list_display   = ["user", "network", "token", "address_short", "is_active", "created_at"]
    list_filter    = ["network", "token", "is_active"]
    search_fields  = ["user__email", "address"]
    readonly_fields = ["address", "encrypted_private_key", "encrypted_keypair",
                       "derivation_index", "created_at"]

    def address_short(self, obj):
        return obj.address[:16] + "…" if len(obj.address) > 16 else obj.address
    address_short.short_description = "Address"


@admin.register(DepositTransaction)
class DepositTransactionAdmin(admin.ModelAdmin):
    list_display   = [
        "user", "network", "token", "amount", "amount_usd", "credits_added",
        "status", "detected_at", "credited_at",
    ]
    list_filter    = ["network", "token", "status"]
    search_fields  = ["user__email", "tx_hash"]
    readonly_fields = [
        "deposit_address", "user", "tx_hash", "network", "token",
        "amount", "amount_usd", "credits_added", "block_number",
        "detected_at", "credited_at", "swept_at", "sweep_tx_hash", "raw_data",
    ]
    ordering = ["-detected_at"]

    actions = ["retry_sweep"]

    @admin.action(description="Retry sweep to treasury for selected transactions")
    def retry_sweep(self, request, queryset):
        from .blockchain_scanner import sweep_bep20, sweep_solana
        swept, failed = 0, 0
        for dep_tx in queryset.filter(status__in=["sweep_failed", "credited"]):
            try:
                if dep_tx.network == "bep20":
                    ok = sweep_bep20(dep_tx)
                elif dep_tx.network == "solana":
                    ok = sweep_solana(dep_tx)
                else:
                    ok = False
                swept += 1 if ok else 0
                failed += 0 if ok else 1
            except Exception:
                failed += 1
        self.message_user(request, f"Swept: {swept}, Failed: {failed}")


@admin.register(BlockScanState)
class BlockScanStateAdmin(admin.ModelAdmin):
    list_display  = ["network", "last_scanned_block", "last_scan_at", "error_count"]
    readonly_fields = ["network", "last_scanned_block", "last_scan_at",
                       "error_count", "last_error"]


admin.site.site_header = 'ADMIN'
admin.site.site_title = 'ADMINISTRATION'


# admin.site.index_template = None  # reset if already set

# # Override the site header to inject CSS
# class MyAdminSite(admin.AdminSite):
#     def each_context(self, request):
#         context = super().each_context(request)
#         return context