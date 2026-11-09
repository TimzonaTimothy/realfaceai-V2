from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import Account
from .deposit_views import _get_or_create_deposit_address

@receiver(post_save, sender=Account)
def create_deposit_addresses(sender, instance, created, **kwargs):
    if created:
        for network, token in [("bep20", "USDT"),
                                ("solana", "USDT"), ("solana", "USDC")]:
            try:
                _get_or_create_deposit_address(instance, network, token)
            except Exception as e:
                import logging
                logging.getLogger(__name__).error(
                    f"Failed to create {token}/{network} address for "
                    f"{instance.email}: {e}"
                )