"""
Management command: run_sweeper
================================
Sweeps credited deposits from user deposit wallets to the master treasury.

cPanel cron — run every 1 minute:
    * * * * * /home/<user>/virtualenv/<env>/bin/python /home/<user>/public_html/manage.py run_sweeper >> /home/<user>/logs/run_sweeper.log 2>&1
"""

import time
import logging

from django.core.management.base import BaseCommand
from django.utils import timezone

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Sweep credited deposits from user wallets to the master treasury."

    def handle(self, *args, **options):
        from account.blockchain_scanner import run_sweeper

        started_at = timezone.now()
        self.stdout.write(f"[{started_at.isoformat()}] Starting sweeper...")

        t0 = time.time()
        try:
            result = run_sweeper()
            elapsed = round(time.time() - t0, 2)
            self.stdout.write(
                self.style.SUCCESS(
                    f"[{timezone.now().isoformat()}] Sweeper done in {elapsed}s — {result}"
                )
            )
        except Exception as e:
            elapsed = round(time.time() - t0, 2)
            self.stderr.write(
                self.style.ERROR(
                    f"[{timezone.now().isoformat()}] Sweeper FAILED after {elapsed}s: {e}"
                )
            )
            logger.exception("[run_sweeper] Unhandled error")


# python manage.py run_sweeper