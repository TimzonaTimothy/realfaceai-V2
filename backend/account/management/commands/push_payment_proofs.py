"""
Retry the Cloudinary mirror for payment proofs that are only stored locally.

    python manage.py push_payment_proofs

Safe to run from cron (e.g. every 15 minutes). Proofs are already viewable
from the local copy, so this is housekeeping, not a rescue.
"""
from django.core.management.base import BaseCommand
from django.db.models import Q

from account.models import PaymentProof
from account.proof_views import push_proof_to_cloudinary


class Command(BaseCommand):
    help = "Mirror locally-stored payment proofs to Cloudinary."

    def add_arguments(self, parser):
        parser.add_argument("--limit", type=int, default=50)

    def handle(self, *args, **opts):
        qs = (
            PaymentProof.objects
            .exclude(Q(local_image__isnull=True) | Q(local_image=""))
            .filter(Q(proof_image__isnull=True) | Q(proof_image=""))
        )
        ok = failed = 0
        for proof in qs.order_by("submitted_at")[: opts["limit"]]:
            if push_proof_to_cloudinary(proof.pk):
                ok += 1
            else:
                failed += 1
        self.stdout.write(self.style.SUCCESS(f"Mirrored {ok}, failed {failed}."))