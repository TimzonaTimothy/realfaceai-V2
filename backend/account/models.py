from django.db import models
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager,PermissionsMixin, Group, Permission
from django.db.models import Q
from django.utils import timezone
from django.conf import settings
from datetime import timedelta
from decimal import Decimal
from django.template.loader import render_to_string
from django.core.mail import EmailMessage
import uuid
import secrets
import hashlib
from cloudinary_storage.storage import MediaCloudinaryStorage
import os
from django.core.files.storage import FileSystemStorage


def private_proof_storage():
    """
    Local, NON-public disk storage for payment-proof screenshots.

    Files land in <BASE_DIR>/private_media/ — outside MEDIA_ROOT and outside
    public_html, so they are never directly reachable by URL. Admins view
    them through the admin (PaymentProofAdmin.image_view) and users through
    the authenticated API (proof_views.proof_image).
    """
    location = getattr(settings, 'PRIVATE_MEDIA_ROOT', None) or os.path.join(settings.BASE_DIR, 'private_media')
    return FileSystemStorage(location=location)

class MyAccountManager(BaseUserManager):
    def create_user(self,email,password=None):
        if not email:
            raise ValueError('User must have an email address')

        # if not account_number:
        #     raise ValueError('User must have account number')

        user = self.model(
            email = self.normalize_email(email),
        )

        user.set_password(password)
        user.save(using=self._db)
        
        return user

    def create_superuser(self,email,password):
        user = self.create_user(
            email = self.normalize_email(email),
            password=password,
        )

        user.is_admin = True
        user.is_active = True
        user.is_staff = True
        user.is_superadmin = True
        user.is_superuser = True

        user.save(using=self._db)
        return user


class Account(AbstractBaseUser,PermissionsMixin):
    # ── Account status (see account/account_status.py) ───────────────────────
    #   active    — normal use
    #   frozen    — can sign in and VIEW (dashboard, usage, billing history)
    #               but every write is refused: no streaming, generation,
    #               payments or proof uploads. Live streams stop on the next
    #               heartbeat.
    #   suspended — fully locked out: sign-in, token refresh and every API
    #               call are refused. Live streams stop on the next heartbeat.
    # Change it through account_status.change_account_status() (admin, staff
    # API and management command all do) so every change is audited.
    STATUS_ACTIVE    = "active"
    STATUS_FROZEN    = "frozen"
    STATUS_SUSPENDED = "suspended"
    STATUS_CHOICES = [
        (STATUS_ACTIVE,    "Active"),
        (STATUS_FROZEN,    "Frozen (read-only)"),
        (STATUS_SUSPENDED, "Suspended (locked out)"),
    ]

    email         = models.EmailField(max_length=100, unique=True)

    account_status    = models.CharField(
        max_length=16, choices=STATUS_CHOICES, default=STATUS_ACTIVE, db_index=True,
    )
    status_reason     = models.CharField(
        max_length=500, blank=True, default="",
        help_text="Shown to the user in the app and in the notification email.",
    )
    status_note       = models.TextField(
        blank=True, default="", help_text="Internal only — never shown to the user.",
    )
    status_expires_at = models.DateTimeField(
        null=True, blank=True,
        help_text="Leave empty for indefinite. When this time passes the account "
                  "is restored to active automatically.",
    )
    status_changed_at = models.DateTimeField(null=True, blank=True, editable=False)
    status_changed_by = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.SET_NULL,
        related_name="+", editable=False,
    )

    last_activity = models.DateTimeField(auto_now=True,editable=False)

    date_joined   = models.DateTimeField(blank=True,null=True) 
    last_login    = models.DateTimeField(blank=True,null=True)   
    is_admin      = models.BooleanField(default=False)
    is_staff      = models.BooleanField(default=False)
    is_active     = models.BooleanField(default=True)
    is_superadmin = models.BooleanField(default=False)
    is_superuser = models.BooleanField(default=False)

    groups = models.ManyToManyField(
        Group, 
        related_name="account_users",  # Custom related name to avoid conflicts
        blank=True
    )
    
    user_permissions = models.ManyToManyField(
        Permission, 
        related_name="account_users_permissions",  # Custom related name
        blank=True
    )

    USERNAME_FIELD = 'email'
    # REQUIRED_FIELDS = ['first_name', 'last_name', ]

    objects = MyAccountManager()
        
    def full_name(self):
        return f"{self.first_name} {self.last_name}"

    def has_perm(self, perm, obj=None):
        return self.is_admin
    
    def has_module_perms(self, app_label):
        return self.is_superuser

    def has_module_perms(self, add_label):
        return True
    
    class Meta:
        ordering = ["-date_joined"]

    @property
    def is_suspended(self):
        return self.account_status == self.STATUS_SUSPENDED

    @property
    def is_frozen(self):
        return self.account_status == self.STATUS_FROZEN


class AccountStatusLog(models.Model):
    """Append-only audit trail of every account status change."""
    SOURCE_ADMIN   = "admin"
    SOURCE_API     = "api"
    SOURCE_COMMAND = "command"
    SOURCE_EXPIRY  = "auto_expiry"
    SOURCE_SYSTEM  = "system"
    SOURCE_CHOICES = [
        (SOURCE_ADMIN,   "Django admin"),
        (SOURCE_API,     "Staff API"),
        (SOURCE_COMMAND, "Management command"),
        (SOURCE_EXPIRY,  "Automatic expiry"),
        (SOURCE_SYSTEM,  "System"),
    ]

    account     = models.ForeignKey(Account, on_delete=models.CASCADE, related_name="status_history")
    from_status = models.CharField(max_length=16, choices=Account.STATUS_CHOICES)
    to_status   = models.CharField(max_length=16, choices=Account.STATUS_CHOICES)
    reason      = models.CharField(max_length=500, blank=True, default="")
    note        = models.TextField(blank=True, default="")
    expires_at  = models.DateTimeField(null=True, blank=True)
    actor       = models.ForeignKey(
        Account, null=True, blank=True, on_delete=models.SET_NULL, related_name="+",
    )
    source      = models.CharField(max_length=16, choices=SOURCE_CHOICES, default=SOURCE_SYSTEM)
    created_at  = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "account_status_log"
        ordering = ["-created_at", "-id"]
        verbose_name = "Account status change"
        verbose_name_plural = "Account status history"

    def __str__(self):
        return f"{self.account.email}: {self.from_status} → {self.to_status} ({self.created_at:%Y-%m-%d %H:%M})"


class UserProfile(models.Model):
    PLAN_FREE = "free"

    PLAN_CHOICES = [
        ("free",     "Free"),
        ("elite",    "Elite"),
        ("icon",     "Icon"),
        ("platinum", "Platinum"),
        ("diamond",  "Diamond"),
        ("infinity", "Infinity"),
    ]
    user = models.OneToOneField(Account, on_delete=models.CASCADE)
    credits = models.DecimalField(
        max_digits=14,
        decimal_places=4,
        default=Decimal("0.0000"),
    )
    plan = models.CharField(max_length=20, choices=PLAN_CHOICES, default=PLAN_FREE)


    def has_credits(self, amount):
        """Check if user has enough credits."""
        return self.credits >= Decimal(str(amount))


    def deduct_credits(self, amount):
        """
        Deduct credits from user balance.
        Raises ValueError if insufficient credits.
        """
        amount = Decimal(str(amount))
        if not self.has_credits(amount):
            raise ValueError(
                f"Insufficient credits. Required: {amount}, Available: {self.credits}"
            )
        self.credits -= amount
        self.save(update_fields=["credits"])
        return self.credits
 
    def add_credits(self, amount):
        """Add credits to user balance (called after payment confirms)."""
        amount = Decimal(str(amount))
        self.credits += amount
        self.save(update_fields=["credits"])
        return self.credits
 
    def __str__(self):
        return f"{self.user.email} | {self.credits} credits"
    
    
    def maybe_upgrade_plan(self) -> bool:
        """
        Check if the user's current credit balance qualifies them for a higher plan.
        Walks from highest plan to lowest and upgrades if threshold is met.
        Returns True if the plan was changed.
        """
        from django.conf import settings

        thresholds    = settings.PLAN_CREDIT_THRESHOLDS      # {"core": 1000, ...}
        upgrade_order = settings.PLAN_UPGRADE_ORDER          # ["nova", "titan", ...]
        current_plan  = self.plan

        for plan_name in upgrade_order:
            required = thresholds.get(plan_name, 0)
            if self.credits >= required:
                if current_plan != plan_name:
                    self.plan = plan_name
                    self.save(update_fields=["plan"])
                    return True
                break  # already on the best qualifying plan, nothing to do

        return False



class UsageLog(models.Model):
    """
    Every API call is recorded here.
    Used for: dashboard charts, billing reconciliation, debugging.
    """
    ENDPOINT_REALTIME = "realtime_token"
    ENDPOINT_VIDEO = "queue_video"
    ENDPOINT_IMAGE = "queue_image"
 
    ENDPOINT_CHOICES = [
        (ENDPOINT_REALTIME, "Realtime Token (WebRTC)"),
        (ENDPOINT_VIDEO,    "Queue: Video Generation"),
        (ENDPOINT_IMAGE,    "Queue: Image Generation"),
    ]
 
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="usage_logs",
    )
    endpoint = models.CharField(max_length=50, choices=ENDPOINT_CHOICES)
    model_used = models.CharField(max_length=100, blank=True)
    credits_used = models.DecimalField(max_digits=12, decimal_places=4)
    timestamp = models.DateTimeField(auto_now_add=True)
    # Extra info: prompt text, resolution, duration etc.
    metadata = models.JSONField(default=dict, blank=True)
 
    class Meta:
        db_table = "users_usagelog"
        ordering = ["-timestamp"]
        indexes = [
            models.Index(fields=["user", "timestamp"]),
            models.Index(fields=["endpoint"]),
        ]
 
    def __str__(self):
        return f"{self.user.email} | {self.endpoint} | {self.credits_used} credits"
 

def generate_payment_id():
    """
    Random public-facing payment reference, e.g. 'PYM-4X7B2QQK'.
    Not sequential/guessable like the internal auto-increment pk.
    """
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I to avoid confusion
    suffix = "".join(secrets.choice(alphabet) for _ in range(8))
    return f"PYM-{suffix}"

class CryptoPayment(models.Model):
    """
    Tracks every crypto payment.
    When status becomes 'confirmed', credits are added to user account.
    """
    STATUS_WAITING    = "waiting"
    STATUS_CONFIRMING = "confirming"
    STATUS_CONFIRMED  = "confirmed"
    STATUS_FAILED     = "failed"
    STATUS_EXPIRED    = "expired"
 
    STATUS_CHOICES = [
        (STATUS_WAITING,    "Waiting for payment"),
        (STATUS_CONFIRMING, "Confirming"),
        (STATUS_CONFIRMED,  "Confirmed — credits added"),
        (STATUS_FAILED,     "Failed"),
        (STATUS_EXPIRED,    "Expired"),
    ]
 
    GATEWAY_CRYPTO      = "crypto"
 
    GATEWAY_CHOICES = [
        (GATEWAY_CRYPTO,      "Crypto"),
    ]
    
    payment_id = models.CharField(
        max_length=20,
        unique=True,
        editable=False,
        db_index=True,
        default=generate_payment_id,
        help_text="Random public payment reference (e.g. PYM-4X7B2QQK).",
    )
    user       = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="payments",
    )
    pack_id    = models.CharField(max_length=50)
    pack_label = models.CharField(max_length=100, blank=True)
 
    # Payment amounts
    amount_usd     = models.DecimalField(max_digits=10, decimal_places=2)
    credits_to_add = models.IntegerField()
    currency       = models.CharField(max_length=30)  # "btc", "eth", "usdttrc20", "NGN", "USD", etc.
 
    # Which gateway processed this payment
    gateway = models.CharField(
        max_length=20,
        choices=GATEWAY_CHOICES,
        default=GATEWAY_CRYPTO,
    )
 
    # Crypto references
    payment_url            = models.URLField(blank=True)

    # The wallet the user was told to pay into. Stored so the same address is
    # shown every time the instructions are reopened, and so the admin knows
    # which wallet to check when verifying.
    wallet_address = models.CharField(max_length=255, blank=True, default="")
    wallet_label   = models.CharField(max_length=100, blank=True, default="")
 
    status       = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_WAITING)
    created_at   = models.DateTimeField(auto_now_add=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)
 
    class Meta:
        db_table = "payments_cryptopayment"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "status"]),
        ]
 
    def __str__(self):
        return f"{self.user.email} | {self.pack_label} | {self.gateway} | {self.status}"
        
    def save(self, *args, **kwargs):
        # Guard against the astronomically unlikely case of a collision.
        if not self.pk:
            while CryptoPayment.objects.filter(payment_id=self.payment_id).exists():
                self.payment_id = generate_payment_id()
        super().save(*args, **kwargs)




class PaymentProof(models.Model):
    """
    One row per proof SUBMISSION — a CryptoPayment can have many of these
    (every re-upload creates a new row rather than overwriting the last one).

    Storage:
      local_image  — written to the server's disk INSIDE the request, before
                     we reply. This is the source of truth: once the user sees
                     "Proof submitted", the file is already safely stored.
      proof_image  — a Cloudinary mirror, pushed afterwards on a background
                     thread (best effort). If that thread is killed by the
                     host or Cloudinary is down, nothing is lost — admin and
                     user both fall back to local_image.
    """
    STATUS_PENDING  = "pending"    # saved locally, Cloudinary mirror not done yet
    STATUS_UPLOADED = "uploaded"   # saved locally AND mirrored to Cloudinary
    STATUS_FAILED   = "failed"     # Cloudinary mirror failed (local copy still fine)

    STATUS_CHOICES = [
        (STATUS_PENDING,  "Pending"),
        (STATUS_UPLOADED, "Uploaded"),
        (STATUS_FAILED,   "Failed"),
    ]

    payment     = models.ForeignKey(CryptoPayment, on_delete=models.CASCADE, related_name='proofs')
    proof_image = models.ImageField(
        upload_to='payment_proofs/', storage=MediaCloudinaryStorage(), blank=True, null=True,
    )
    local_image = models.FileField(
        upload_to='payment_proofs/%Y/%m/', storage=private_proof_storage,
        blank=True, null=True, max_length=255,
    )
    original_filename = models.CharField(max_length=255, blank=True, default='')
    tx_hash     = models.CharField(max_length=255, blank=True)
    notes       = models.TextField(blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)
    upload_status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
    )
    upload_error = models.TextField(blank=True, default='')
    idempotency_key = models.CharField(
        max_length=64, blank=True, null=True, db_index=True,
        help_text='Client-generated key for this submission attempt. Lets '
                   'a retried request (after a dropped connection) be '
                   're-acknowledged instead of reprocessed as a new row.',
    )

    class Meta:
        ordering = ['-submitted_at']

    def __str__(self):
        return f'Proof for Payment #{self.payment.id} — {self.payment.user.email}'

    @property
    def has_image(self) -> bool:
        """True when we actually hold the image (locally or on Cloudinary)."""
        return bool(self.local_image) or bool(self.proof_image)


class PasswordResetOTP(models.Model):
    """
    Stores a 6-digit OTP for desktop app password resets.
    - Each code expires after 10 minutes.
    - Requesting a new code invalidates all previous ones for that user.
    - Max 3 verification attempts before the code is burned.
    """
    user       = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="password_otps",
    )
    code       = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used    = models.BooleanField(default=False)
    attempts   = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = "account_password_reset_otp"
        ordering = ["-created_at"]

    def is_expired(self):
        return timezone.now() > self.expires_at

    def is_valid(self):
        return not self.is_used and not self.is_expired() and self.attempts < 3

    @classmethod
    def create_for_user(cls, user):
        """Invalidate old OTPs and create a fresh 6-digit code (10 min expiry)."""
        import random
        cls.objects.filter(user=user, is_used=False).update(is_used=True)
        code = f"{random.randint(0, 999999):06d}"
        return cls.objects.create(
            user=user,
            code=code,
            expires_at=timezone.now() + timedelta(minutes=10),
        )

    def __str__(self):
        return f"OTP {self.code} for {self.user.email} ({'valid' if self.is_valid() else 'expired/used'})"

class CryptoWallet(models.Model):
    """
    Admin-managed crypto wallet addresses.
    Multiple wallets can exist per network; the API returns one chosen
    at random so consecutive payments to the same network get different
    addresses, making on-chain reconciliation easier.
    """
    network = models.CharField(
        max_length=50,
        help_text=(
            'Currency/network key that matches what the Flutter app sends, '
            'e.g. usdttrc20, usdterc20, usdc, btc, eth, sol'
        ),
    )
    label = models.CharField(
        max_length=100,
        help_text='Human-readable label shown in the app, e.g. "USDT TRC20"',
    )
    address = models.CharField(max_length=255)
    is_active = models.BooleanField(
        default=True,
        help_text='Only active wallets are ever returned to users',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    notes = models.TextField(
        blank=True,
        help_text='Internal notes — never shown to users',
    )

    class Meta:
        db_table = 'account_cryptowallet'
        ordering = ['network', 'id']
        verbose_name = 'Crypto Wallet'
        verbose_name_plural = 'Crypto Wallets'

    def __str__(self):
        short = self.address[:12] + '…' if len(self.address) > 12 else self.address
        return f'{self.label} | {short} ({"active" if self.is_active else "inactive"})'


class FiatCurrency(models.Model):
    """
    Admin-managed list of fiat currencies shown in the app.
    Add, remove or reorder currencies here without touching Flutter code.
    """
    currency_id = models.CharField(
        max_length=10,
        unique=True,
        help_text='ISO code, e.g. NGN, USD, GHS',
    )
    label = models.CharField(
        max_length=50,
        help_text='Display name shown on the chip, e.g. NGN',
    )
    flag = models.CharField(
        max_length=10,
        default='🌍',
        help_text='Flag emoji shown on the chip, e.g. 🇳🇬',
    )
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(
        default=0,
        help_text='Lower number = shown first in the list',
    )

    class Meta:
        db_table = 'account_fiatcurrency'
        ordering = ['sort_order', 'id']
        verbose_name = 'Fiat Currency'
        verbose_name_plural = 'Fiat Currencies'

    def __str__(self):
        return f'{self.flag} {self.label} ({self.currency_id})'






class UserDepositAddress(models.Model):
    """
    Each user gets one unique blockchain address per network+token pair.
    Funds sent here are automatically detected and credited.
    """
    NETWORK_BEP20  = "bep20"
    NETWORK_SOLANA = "solana"
    NETWORK_CHOICES = [
        (NETWORK_BEP20,  "BEP-20 (BSC)"),
        (NETWORK_SOLANA, "Solana"),
    ]
    TOKEN_CHOICES = [
        ("USDT", "USDT"),
        ("USDC", "USDC"),
    ]

    user    = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="deposit_addresses",
    )
    network = models.CharField(max_length=20, choices=NETWORK_CHOICES)
    token   = models.CharField(max_length=10, choices=TOKEN_CHOICES, default="USDT")
    address = models.CharField(max_length=255, unique=True)

    # Encrypted secrets for the wallet sweeper
    encrypted_private_key = models.TextField(blank=True, default="")  # BEP-20
    encrypted_keypair     = models.TextField(blank=True, default="")  # Solana

    # BEP-20 HD derivation index
    derivation_index = models.PositiveIntegerField(
        null=True, blank=True,
        help_text="HD wallet derivation index (BEP-20 only)",
    )

    is_active  = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table       = "account_user_deposit_address"
        unique_together = [("user", "network", "token")]
        ordering        = ["-created_at"]

    def __str__(self):
        return f"{self.user.email} | {self.token} on {self.get_network_display()} | {self.address[:12]}…"


class DepositTransaction(models.Model):
    """Records every on-chain deposit detected by the blockchain scanner."""
    STATUS_DETECTED      = "detected"
    STATUS_CREDITED      = "credited"
    STATUS_SWEEP_PENDING = "sweep_pending"
    STATUS_SWEPT         = "swept"
    STATUS_SWEEP_FAILED  = "sweep_failed"

    STATUS_CHOICES = [
        (STATUS_DETECTED,      "Detected"),
        (STATUS_CREDITED,      "Credited"),
        (STATUS_SWEEP_PENDING, "Sweep Pending"),
        (STATUS_SWEPT,         "Swept to Treasury"),
        (STATUS_SWEEP_FAILED,  "Sweep Failed"),
    ]

    deposit_address = models.ForeignKey(
        UserDepositAddress,
        on_delete=models.CASCADE,
        related_name="transactions",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="deposit_transactions",
    )
    tx_hash      = models.CharField(max_length=255, unique=True)
    network      = models.CharField(max_length=20)
    token        = models.CharField(max_length=10)
    amount       = models.DecimalField(max_digits=20, decimal_places=6)
    amount_usd   = models.DecimalField(max_digits=20, decimal_places=2, default=0)
    credits_added = models.DecimalField(max_digits=20, decimal_places=4, default=0)
    status       = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_DETECTED)
    block_number = models.BigIntegerField(null=True, blank=True)
    detected_at  = models.DateTimeField(auto_now_add=True)
    credited_at  = models.DateTimeField(null=True, blank=True)
    swept_at     = models.DateTimeField(null=True, blank=True)
    sweep_tx_hash = models.CharField(max_length=255, blank=True, default="")
    raw_data     = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "account_deposit_transaction"
        ordering = ["-detected_at"]
        indexes  = [
            models.Index(fields=["tx_hash"]),
            models.Index(fields=["user", "status"]),
            models.Index(fields=["network", "status"]),
        ]

    def __str__(self):
        return (
            f"{self.user.email} | {self.amount} {self.token} on {self.network} "
            f"| {self.status} | {self.tx_hash[:16]}…"
        )


class BlockScanState(models.Model):
    """Tracks which block was last scanned per network (prevents re-processing)."""
    network             = models.CharField(max_length=20, unique=True)
    last_scanned_block  = models.BigIntegerField(default=0)
    last_scan_at        = models.DateTimeField(null=True, blank=True)
    error_count         = models.PositiveIntegerField(default=0)
    last_error          = models.TextField(blank=True, default="")

    class Meta:
        db_table = "account_block_scan_state"

    def __str__(self):
        return f"{self.network} | last block {self.last_scanned_block}"