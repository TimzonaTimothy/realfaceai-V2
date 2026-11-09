from django.urls import path, re_path
from .views import *
from .views import DesktopVerifyOTPView
from django.conf import settings
from django.conf.urls.static import static
from django.views.static import serve

 
from .views import (
    RegisterView,
    LoginView,
    MeView,
    DashboardStatsView,
    PollStatusView,
    UsageLogListView,
    AccountStatusTokenRefreshView,
    AdminAccountStatusView,
)

from .payment_views import (
    CreditPacksView,
    WalletAddressesView,
    CurrenciesView,
    CreatePaymentView,
    PaymentHistoryView,
    PaymentStatusView,
)
from .proof_views import submit_payment_proof, list_payment_proofs, ProofImageView

app_name = 'account'

urlpatterns = [
    path('download/', download_app_view, name='download_app'),
    
    # Auth
    path("register/",  RegisterView.as_view(),       name="register"),
    path("login/",     LoginView.as_view(),           name="login"),
    # Refresh refuses suspended accounts (see AccountStatusTokenRefreshSerializer)
    path("refresh/",   AccountStatusTokenRefreshView.as_view(), name="token_refresh"),
 
    # Profile
    path("me/",        MeView.as_view(),              name="me"),
 
    # Dashboard & polling (replaces WebSocket)
    path("dashboard/", DashboardStatsView.as_view(),  name="dashboard"),
    path("poll/",      PollStatusView.as_view(),      name="poll"),
 
    # Usage history
    path("usage/",     UsageLogListView.as_view(),    name="usage"),


    # ── Shared ────────────────────────────────────────────────────────────────
    path("packs/",                   CreditPacksView.as_view(),    name="credit_packs"),
    path("payments/wallets/",        WalletAddressesView.as_view(), name="wallet_addresses"),
    path("payments/currencies/",     CurrenciesView.as_view(),       name="currencies"),
    path("payments/",                         PaymentHistoryView.as_view(), name="payment_history"),
    path("<str:payment_id>/status/", PaymentStatusView.as_view(),  name="payment_status"),
 
    # ── Crypto ──────────────────────────────────────────────────
    path("payments/create/",   CreatePaymentView.as_view(),  name="create_crypto_payment"),
    path("payments/<str:payment_id>/proof/",  submit_payment_proof, name="submit_payment_proof"),
    path("payments/<str:payment_id>/proofs/", list_payment_proofs,  name="payment_proofs"),
    path("payments/<str:payment_id>/proofs/<int:proof_id>/image/",
         ProofImageView.as_view(), name="payment_proof_image"),

    # ── Desktop App — password management (uses Gmail/streamai51) ─────────────
    path("desktop/forgot-password/",  DesktopForgotPasswordView.as_view(),  name="desktop_forgot_password"),
    path("desktop/verify-otp/",       DesktopVerifyOTPView.as_view(),       name="desktop_verify_otp"),
    path("desktop/change-password/",  DesktopChangePasswordView.as_view(),  name="desktop_change_password"),

    # ── Staff — suspend / freeze / reactivate an account ──────────────────────
    path("admin/accounts/<str:identifier>/status/", AdminAccountStatusView.as_view(), name="admin_account_status"),
]+ static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)