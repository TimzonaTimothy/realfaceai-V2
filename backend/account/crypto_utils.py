"""
crypto_utils.py
===============
Wallet generation and encryption helpers for BEP-20 (BSC) and Solana.

Requirements (add to your requirements.txt):
    web3>=6.0.0
    eth-account>=0.8.0
    solders>=0.18.0          # fast Solana keypair (Rust-backed)
    cryptography>=41.0.0     # Fernet symmetric encryption
    bip_utils>=2.7.0         # HD BIP-44 derivation for BEP-20

Environment variables (add to .env / settings):
    WALLET_ENCRYPTION_KEY       32-byte Fernet key (generate once: Fernet.generate_key())
    BSC_MASTER_MNEMONIC         12/24-word BIP-39 mnemonic for HD wallet (BEP-20)
    BSC_TREASURY_ADDRESS        Master BSC address to sweep funds to
    BSC_RPC_URL                 e.g. https://bsc-dataseed.binance.org/
    SOL_TREASURY_ADDRESS        Master Solana address to sweep funds to
    SOL_RPC_URL                 e.g. https://api.mainnet-beta.solana.com
    USDT_BEP20_CONTRACT         0x55d398326f99059ff775485246999027b3197955
    USDC_BEP20_CONTRACT         0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
    USDT_SOLANA_MINT            Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB
    USDC_SOLANA_MINT            EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
    CREDITS_PER_USD             50   (how many credits per $1 USD)
"""

import base64
import json
import logging
import threading
from decimal import Decimal
from functools import lru_cache

from cryptography.fernet import Fernet
from django.conf import settings

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# THREAD LOCK for BEP-20 index allocation
# select_for_update() is a no-op on SQLite, so we use a process-level lock
# to serialise concurrent calls to get_next_bep20_index().
# ─────────────────────────────────────────────────────────────────────────────

_bep20_index_lock = threading.Lock()


# ─────────────────────────────────────────────────────────────────────────────
# ENCRYPTION
# ─────────────────────────────────────────────────────────────────────────────

@lru_cache(maxsize=1)
def _fernet() -> Fernet:
    key = getattr(settings, "WALLET_ENCRYPTION_KEY", "")
    if not key:
        raise RuntimeError("WALLET_ENCRYPTION_KEY is not configured")
    if isinstance(key, str):
        key = key.encode()
    return Fernet(key)


def encrypt_secret(plaintext: str) -> str:
    """Encrypt a private key / keypair bytes to a base64-encoded ciphertext."""
    return _fernet().encrypt(plaintext.encode()).decode()


def decrypt_secret(ciphertext: str) -> str:
    """Decrypt back to original plaintext."""
    return _fernet().decrypt(ciphertext.encode()).decode()


# ─────────────────────────────────────────────────────────────────────────────
# BEP-20 / BSC WALLET GENERATION  (HD BIP-44 derivation)
# ─────────────────────────────────────────────────────────────────────────────

def generate_bep20_wallet(derivation_index: int) -> dict:
    """
    Derive a deterministic BEP-20 wallet from the master mnemonic.
    Path: m/44'/60'/0'/0/<index>

    Returns:
        {
          "address": "0x...",
          "encrypted_private_key": "<fernet-ciphertext>",
          "derivation_index": int,
        }
    """
    try:
        from bip_utils import (
            Bip39MnemonicValidator, Bip39SeedGenerator,
            Bip44, Bip44Coins, Bip44Changes,
        )
    except ImportError:
        raise RuntimeError("bip_utils is required: pip install bip_utils")

    mnemonic = getattr(settings, "BSC_MASTER_MNEMONIC", "")
    if not mnemonic:
        raise RuntimeError("BSC_MASTER_MNEMONIC is not configured")

    # Validate mnemonic
    if not Bip39MnemonicValidator().IsValid(mnemonic):
        raise RuntimeError("BSC_MASTER_MNEMONIC is invalid")

    seed_bytes = Bip39SeedGenerator(mnemonic).Generate()
    bip44_mst  = Bip44.FromSeed(seed_bytes, Bip44Coins.ETHEREUM)
    bip44_acc  = (
        bip44_mst
        .Purpose()
        .Coin()
        .Account(0)
        .Change(Bip44Changes.CHAIN_EXT)
        .AddressIndex(derivation_index)
    )

    private_key_hex = bip44_acc.PrivateKey().Raw().ToHex()
    address         = bip44_acc.PublicKey().ToAddress()

    return {
        "address":               address,
        "encrypted_private_key": encrypt_secret(private_key_hex),
        "derivation_index":      derivation_index,
    }


def _get_next_bep20_index_locked() -> int:
    """
    Return the next unused HD derivation index.
    MUST be called while already holding _bep20_index_lock.
    """
    from account.models import UserDepositAddress
    from django.db import transaction
    with transaction.atomic():
        max_idx = (
            UserDepositAddress.objects
            .filter(network="bep20")
            .order_by("-derivation_index")
            .values_list("derivation_index", flat=True)
            .first()
        )
        return (max_idx or -1) + 1


def get_next_bep20_index() -> int:
    """
    Return the next unused HD derivation index (acquires the lock itself).
    Use _get_next_bep20_index_locked() if you already hold the lock.
    """
    with _bep20_index_lock:
        return _get_next_bep20_index_locked()


# ─────────────────────────────────────────────────────────────────────────────
# SOLANA WALLET GENERATION  (random keypair per user)
# ─────────────────────────────────────────────────────────────────────────────

def generate_solana_wallet() -> dict:
    """
    Generate a fresh random Solana keypair.

    Returns:
        {
          "address": "<base58 pubkey>",
          "encrypted_keypair": "<fernet-encrypted base64 of 64-byte secret seed>",
        }
    """
    try:
        from solders.keypair import Keypair
    except ImportError:
        raise RuntimeError("solders is required: pip install solders")

    kp      = Keypair()
    address = str(kp.pubkey())
    # Store the full 64-byte secret key (seed + pubkey) as base64
    secret_b64 = base64.b64encode(bytes(kp)).decode()

    return {
        "address":           address,
        "encrypted_keypair": encrypt_secret(secret_b64),
    }


# ─────────────────────────────────────────────────────────────────────────────
# TOKEN CONTRACTS / MINT ADDRESSES
# ─────────────────────────────────────────────────────────────────────────────

BEP20_TOKEN_CONTRACTS = {
    "USDT": lambda: getattr(settings, "USDT_BEP20_CONTRACT", "0x55d398326f99059ff775485246999027b3197955"),
    "USDC": lambda: getattr(settings, "USDC_BEP20_CONTRACT", "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d"),
}

SOLANA_MINT_ADDRESSES = {
    "USDT": lambda: getattr(settings, "USDT_SOLANA_MINT", "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"),
    "USDC": lambda: getattr(settings, "USDC_SOLANA_MINT", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
}

# Standard ERC-20 / BEP-20 ABI (Transfer event only — enough for scanning)
ERC20_ABI = json.loads("""[
  {"anonymous":false,"inputs":[{"indexed":true,"name":"from","type":"address"},
   {"indexed":true,"name":"to","type":"address"},
   {"indexed":false,"name":"value","type":"uint256"}],
   "name":"Transfer","type":"event"},
  {"constant":true,"inputs":[{"name":"_owner","type":"address"}],
   "name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],
   "type":"function"},
  {"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],
   "name":"transfer","outputs":[{"name":"","type":"bool"}],"type":"function"},
  {"constant":true,"inputs":[],"name":"decimals",
   "outputs":[{"name":"","type":"uint8"}],"type":"function"}
]""")


# ─────────────────────────────────────────────────────────────────────────────
# CREDIT CALCULATION
# ─────────────────────────────────────────────────────────────────────────────

def usd_to_credits(amount_usd: Decimal) -> Decimal:
    """Convert a USD amount to platform credits."""
    rate = Decimal(str(getattr(settings, "CREDITS_PER_USD", "50")))
    return (amount_usd * rate).quantize(Decimal("0.0001"))