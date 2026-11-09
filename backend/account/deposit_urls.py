"""
deposit_urls.py
===============
Wire these URLs into your main URL conf or payments URL conf.

In deep/urls.py or account/payments_urls.py add:
    from django.urls import path, include
    path("api/v1/payments/deposit/", include("account.deposit_urls")),
"""

from django.urls import path
from .deposit_views import *

urlpatterns = [
    # User-facing
    path("address/",       UserDepositAddressView.as_view(),  name="deposit_address"),
    path("my-addresses/",  AllDepositAddressesView.as_view(), name="deposit_all_addresses"),
    path("history/",       UserDepositHistoryView.as_view(),  name="deposit_history"),

    # Cron — hit every 10 s: GET /api/v1/payments/deposit/scan/
    # Header required: X-Cron-Secret: <your CRON_SECRET>
    path("scan/",          BlockchainScanView.as_view(),      name="deposit_scan"),

    # Cron — split endpoints (recommended — use these instead)
    # Hit bep20 + solana every 10–30 s; sweep every 60 s.
    path("scan/bep20/",    BlockchainScanBEP20View.as_view(), name="deposit_scan_bep20"),
    path("scan/solana/",   BlockchainScanSolanaView.as_view(),name="deposit_scan_solana"),
    path("scan/sweep/",    BlockchainSweeperView.as_view(),   name="deposit_scan_sweep"),
 

    # Admin/debug
    path("status/",        DepositScanStatusView.as_view(),   name="deposit_status"),
]
