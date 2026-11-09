"""
Management command: scan_bep20
==============================
Scans BSC for incoming USDT/USDC deposits to user deposit addresses
and credits user balances.

cPanel cron — run every 1 minute:
    * * * * * /home/<user>/virtualenv/<env>/bin/python /home/<user>/public_html/manage.py scan_bep20 >> /home/<user>/logs/scan_bep20.log 2>&1
"""

import time
import logging

from django.core.management.base import BaseCommand
from django.utils import timezone

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Scan BSC (BEP-20) for new USDT/USDC deposits and credit user balances."

    def handle(self, *args, **options):
        from account.blockchain_scanner import scan_bep20

        started_at = timezone.now()
        self.stdout.write(f"[{started_at.isoformat()}] Starting BEP-20 scan...")

        t0 = time.time()
        try:
            result = scan_bep20()
            elapsed = round(time.time() - t0, 2)
            self.stdout.write(
                self.style.SUCCESS(
                    f"[{timezone.now().isoformat()}] BEP-20 scan done in {elapsed}s — {result}"
                )
            )
        except Exception as e:
            elapsed = round(time.time() - t0, 2)
            self.stderr.write(
                self.style.ERROR(
                    f"[{timezone.now().isoformat()}] BEP-20 scan FAILED after {elapsed}s: {e}"
                )
            )
            logger.exception("[scan_bep20] Unhandled error")


# python manage.py scan_bep20