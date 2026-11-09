"""
Management command: scan_solana
================================
Scans Solana for incoming USDT/USDC SPL token deposits to user deposit
addresses and credits user balances.

cPanel cron — run every 1 minute:
    * * * * * /home/<user>/virtualenv/<env>/bin/python /home/<user>/public_html/manage.py scan_solana >> /home/<user>/logs/scan_solana.log 2>&1
"""

import time
import logging

from django.core.management.base import BaseCommand
from django.utils import timezone

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Scan Solana for new USDT/USDC SPL token deposits and credit user balances."

    def handle(self, *args, **options):
        from account.blockchain_scanner import scan_solana

        started_at = timezone.now()
        self.stdout.write(f"[{started_at.isoformat()}] Starting Solana scan...")

        t0 = time.time()
        try:
            result = scan_solana()
            elapsed = round(time.time() - t0, 2)
            self.stdout.write(
                self.style.SUCCESS(
                    f"[{timezone.now().isoformat()}] Solana scan done in {elapsed}s — {result}"
                )
            )
        except Exception as e:
            elapsed = round(time.time() - t0, 2)
            self.stderr.write(
                self.style.ERROR(
                    f"[{timezone.now().isoformat()}] Solana scan FAILED after {elapsed}s: {e}"
                )
            )
            logger.exception("[scan_solana] Unhandled error")


# python manage.py scan_solana