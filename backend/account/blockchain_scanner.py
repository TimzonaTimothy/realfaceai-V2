"""
blockchain_scanner.py
=====================
Polls BSC and Solana for incoming USDT/USDC transfers to user deposit addresses.
Hit  GET /api/v1/payments/scan/  from your cron-job every 10 seconds.

Flow per network:
  1. Load all active deposit addresses for that network.
  2. Fetch new blocks since last scanned block.
  3. Match Transfer events to our addresses.
  4. Credit user balance atomically (idempotent via tx_hash unique constraint).
  5. Queue sweep → master treasury.
"""

import logging
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from .crypto_utils import (
    BEP20_TOKEN_CONTRACTS, SOLANA_MINT_ADDRESSES, ERC20_ABI,
    decrypt_secret, usd_to_credits,
)
from .models import UserDepositAddress, DepositTransaction, BlockScanState

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

USDT_USD_RATE = Decimal("1.00")   # stablecoins — treat 1 token = $1 USD
USDC_USD_RATE = Decimal("1.00")

STABLECOIN_DECIMALS_BEP20  = 18
STABLECOIN_DECIMALS_SOLANA = 6   # both USDT and USDC on Solana use 6


def _get_scan_state(network: str) -> BlockScanState:
    obj, _ = BlockScanState.objects.get_or_create(network=network)
    return obj


def _save_scan_state(state: BlockScanState, block: int, error: str = ""):
    state.last_scanned_block = block
    state.last_scan_at       = timezone.now()
    if error:
        state.error_count += 1
        state.last_error   = error[:500]
    else:
        state.error_count = 0
        state.last_error  = ""
    state.save()


def _load_watched_addresses(network: str) -> dict:
    """Returns {address_lower: UserDepositAddress} for quick O(1) lookup."""
    qs = UserDepositAddress.objects.filter(
        network=network, is_active=True
    ).select_related("user")
    return {obj.address.lower(): obj for obj in qs}


def _record_deposit(deposit_addr: UserDepositAddress, tx_hash: str, token: str,
                    raw_amount: int, decimals: int, block_number: int, raw_data: dict):
    """
    Idempotently record a deposit, credit the user, and mark for sweeping.
    Returns (DepositTransaction | None) — None if tx already processed.
    """
    amount  = Decimal(raw_amount) / Decimal(10 ** decimals)
    usd_val = amount * (USDT_USD_RATE if token == "USDT" else USDC_USD_RATE)
    credits = usd_to_credits(usd_val)

    try:
        with transaction.atomic():
            dep_tx, created = DepositTransaction.objects.get_or_create(
                tx_hash=tx_hash,
                defaults=dict(
                    deposit_address=deposit_addr,
                    user=deposit_addr.user,
                    network=deposit_addr.network,
                    token=token,
                    amount=amount,
                    amount_usd=usd_val,
                    credits_added=credits,
                    block_number=block_number,
                    raw_data=raw_data,
                    status="detected",
                ),
            )

            if not created:
                logger.info(f"[scanner] tx {tx_hash} already recorded — skipping")
                return None

            # Credit the user
            profile = deposit_addr.user.userprofile
            profile.add_credits(credits)

            # Auto-upgrade plan if accumulated credits meet a threshold
            plan_upgraded = profile.maybe_upgrade_plan()
            if plan_upgraded:
                logger.info(
                    f"[scanner] Plan upgraded → {profile.plan} "
                    f"for {deposit_addr.user.email} "
                    f"(balance: {profile.credits} credits)"
                )

            dep_tx.status      = "credited"
            dep_tx.credited_at = timezone.now()
            dep_tx.save(update_fields=["status", "credited_at"])
            
            logger.info(
                f"[scanner] CREDITED {amount} {token} ({credits} credits) "
                f"→ {deposit_addr.user.email} | tx={tx_hash}"
            )
            return dep_tx

    except Exception as e:
        logger.error(f"[scanner] Error recording deposit {tx_hash}: {e}")
        return None


# ─────────────────────────────────────────────────────────────────────────────
# BEP-20 / BSC SCANNER
# ─────────────────────────────────────────────────────────────────────────────

def scan_bep20() -> dict:
    """
    Scan BSC for incoming USDT and USDC transfers to our deposit addresses.
    Returns a summary dict.
    """
    if not getattr(settings, "AUTO_BLOCKCHAIN_SCAN_ENABLED", True):
        logger.info("[scanner] scan_bep20 skipped — AUTO_BLOCKCHAIN_SCAN_ENABLED is False (manual payments mode).")
        return {"status": "disabled", "reason": "AUTO_BLOCKCHAIN_SCAN_ENABLED is False — payments are manual."}

    try:
        from web3 import Web3
    except ImportError:
        return {"error": "web3 not installed"}

    rpc_url = getattr(settings, "BSC_RPC_URL", "https://bsc-dataseed.binance.org/")
    w3      = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": 15}))

    try:
        block = w3.eth.block_number
        logger.info(f"[scanner] Connected to BSC, block={block}, rpc={rpc_url}")
    except Exception as e:
        return {"error": f"BSC RPC not reachable: {e}"}

    watched  = _load_watched_addresses("bep20")
    if not watched:
        return {"network": "bep20", "skipped": "no deposit addresses"}

    state          = _get_scan_state("bep20")
    latest_block   = w3.eth.block_number
    from_block     = state.last_scanned_block + 1 if state.last_scanned_block else latest_block - 20
    # Cap scan window to 1000 blocks per run to avoid RPC timeout
    to_block       = min(latest_block, from_block + 199)
    from_block_hex = hex(from_block)
    to_block_hex   = hex(to_block)

    deposits_found = 0
    errors         = []

    tokens_to_scan = [
        ("USDT", BEP20_TOKEN_CONTRACTS["USDT"](), STABLECOIN_DECIMALS_BEP20),
        ("USDC", BEP20_TOKEN_CONTRACTS["USDC"](), STABLECOIN_DECIMALS_BEP20),
    ]

    for token_symbol, contract_addr, decimals in tokens_to_scan:
        try:
            contract = w3.eth.contract(
                address=Web3.to_checksum_address(contract_addr),
                abi=ERC20_ABI,
            )

            # Use eth_getLogs via the Transfer event topic
            logs = contract.events.Transfer.get_logs(
                from_block=from_block,
                to_block=to_block,
            )

            for log in logs:
                to_addr = log["args"]["to"].lower()
                if to_addr not in watched:
                    continue

                deposit_addr = watched[to_addr]
                tx_hash      = log["transactionHash"].hex()
                raw_amount   = log["args"]["value"]
                block_num    = log["blockNumber"]

                _record_deposit(
                    deposit_addr=deposit_addr,
                    tx_hash=tx_hash,
                    token=token_symbol,
                    raw_amount=raw_amount,
                    decimals=decimals,
                    block_number=block_num,
                    raw_data={"log_index": log["logIndex"], "contract": contract_addr},
                )
                deposits_found += 1

        except Exception as e:
            err = f"bep20 {token_symbol} scan error: {e}"
            logger.error(f"[scanner] {err}")
            errors.append(err)

    _save_scan_state(state, to_block, "; ".join(errors) if errors else "")

    return {
        "network":         "bep20",
        "scanned_blocks":  f"{from_block}–{to_block}",
        "deposits_found":  deposits_found,
        "errors":          errors,
    }


# ─────────────────────────────────────────────────────────────────────────────
# SOLANA SCANNER
# ─────────────────────────────────────────────────────────────────────────────

def scan_solana() -> dict:
    """
    Scan Solana for incoming USDT and USDC SPL-token transfers.
    Uses getSignaturesForAddress + getTransaction for each deposit address.
    """
    if not getattr(settings, "AUTO_BLOCKCHAIN_SCAN_ENABLED", True):
        logger.info("[scanner] scan_solana skipped — AUTO_BLOCKCHAIN_SCAN_ENABLED is False (manual payments mode).")
        return {"status": "disabled", "reason": "AUTO_BLOCKCHAIN_SCAN_ENABLED is False — payments are manual."}

    try:
        import httpx
    except ImportError:
        try:
            import requests as httpx_compat
            httpx = httpx_compat
        except ImportError:
            return {"error": "httpx or requests not installed"}

    rpc_url  = getattr(settings, "SOL_RPC_URL", "https://api.mainnet-beta.solana.com")
    watched  = _load_watched_addresses("solana")

    if not watched:
        return {"network": "solana", "skipped": "no deposit addresses"}

    state          = _get_scan_state("solana")
    deposits_found = 0
    errors         = []

    # We'll query each address's token accounts for new signatures
    mint_map = {
        "USDT": SOLANA_MINT_ADDRESSES["USDT"](),
        "USDC": SOLANA_MINT_ADDRESSES["USDC"](),
    }

    def _rpc(method, params):
        try:
            resp = httpx.post(
                rpc_url,
                json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
                timeout=15,
            )
            return resp.json().get("result")
        except Exception as e:
            logger.error(f"[scanner] Solana RPC {method} error: {e}")
            return None

    for address, deposit_addr in watched.items():
        for token_symbol, mint_addr in mint_map.items():
            # Find Associated Token Account (ATA) for this wallet + mint
            ata_result = _rpc("getTokenAccountsByOwner", [
                address,
                {"mint": mint_addr},
                {"encoding": "jsonParsed"},
            ])

            if not ata_result or not ata_result.get("value"):
                continue

            for token_account_info in ata_result["value"]:
                ata_address = token_account_info["pubkey"]

                # Get recent signatures for the ATA
                sig_result = _rpc("getSignaturesForAddress", [
                    ata_address,
                    {"limit": 20, "commitment": "confirmed"},
                ])

                if not sig_result:
                    continue

                for sig_info in sig_result:
                    sig = sig_info.get("signature", "")
                    if not sig:
                        continue

                    # Skip already processed
                    if DepositTransaction.objects.filter(tx_hash=sig).exists():
                        continue

                    # Fetch full transaction
                    tx_data = _rpc("getTransaction", [
                        sig,
                        {"encoding": "jsonParsed", "maxSupportedTransactionVersion": 0},
                    ])

                    if not tx_data:
                        continue

                    # Parse SPL token transfer from postTokenBalances vs preTokenBalances
                    try:
                        meta         = tx_data.get("meta", {})
                        pre_bals     = {b["accountIndex"]: b for b in meta.get("preTokenBalances", [])}
                        post_bals    = {b["accountIndex"]: b for b in meta.get("postTokenBalances", [])}
                        account_keys = tx_data["transaction"]["message"]["accountKeys"]

                        for idx, post in post_bals.items():
                            if post.get("mint") != mint_addr:
                                continue
                            acct_pubkey = account_keys[idx]["pubkey"] if isinstance(account_keys[idx], dict) else account_keys[idx]
                            if acct_pubkey != ata_address:
                                continue

                            pre_amount  = int(pre_bals.get(idx, {}).get("uiTokenAmount", {}).get("amount", "0"))
                            post_amount = int(post.get("uiTokenAmount", {}).get("amount", "0"))
                            delta       = post_amount - pre_amount

                            if delta <= 0:
                                continue

                            block_num = tx_data.get("slot", 0)
                            _record_deposit(
                                deposit_addr=deposit_addr,
                                tx_hash=sig,
                                token=token_symbol,
                                raw_amount=delta,
                                decimals=STABLECOIN_DECIMALS_SOLANA,
                                block_number=block_num,
                                raw_data={"slot": block_num, "ata": ata_address},
                            )
                            deposits_found += 1

                    except Exception as e:
                        err = f"Solana parse error sig={sig}: {e}"
                        logger.error(f"[scanner] {err}")
                        errors.append(err)

    _save_scan_state(state, 0, "; ".join(errors) if errors else "")

    return {
        "network":        "solana",
        "deposits_found": deposits_found,
        "errors":         errors,
    }


# ─────────────────────────────────────────────────────────────────────────────
# WALLET SWEEPER  — moves funds from user deposit wallets → master treasury
# ─────────────────────────────────────────────────────────────────────────────

def sweep_bep20(dep_tx: DepositTransaction) -> bool:
    """
    Transfer all USDT/USDC from the user's deposit address to the treasury.
    Gas is paid from the treasury address (or we fund the deposit addr with BNB first).
    Returns True on success.
    """
    try:
        from web3 import Web3
    except ImportError:
        logger.error("[sweeper] web3 not installed")
        return False

    rpc_url      = getattr(settings, "BSC_RPC_URL", "https://bsc-dataseed.binance.org/")
    treasury     = getattr(settings, "BSC_TREASURY_ADDRESS", "")
    treasury_key = getattr(settings, "BSC_TREASURY_PRIVATE_KEY", "")

    if not treasury or not treasury_key:
        logger.error("[sweeper] BSC_TREASURY_ADDRESS or BSC_TREASURY_PRIVATE_KEY not set")
        return False

    w3          = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": 15}))
    deposit_obj = dep_tx.deposit_address
    token       = dep_tx.token

    contract_addr = BEP20_TOKEN_CONTRACTS[token]()
    contract      = w3.eth.contract(
        address=Web3.to_checksum_address(contract_addr),
        abi=ERC20_ABI,
    )

    deposit_addr_checksum = Web3.to_checksum_address(deposit_obj.address)
    private_key_hex       = decrypt_secret(deposit_obj.encrypted_private_key)

    # Current token balance of the deposit address
    balance = contract.functions.balanceOf(deposit_addr_checksum).call()
    if balance == 0:
        logger.info(f"[sweeper] bep20 deposit {deposit_addr_checksum} has zero balance — nothing to sweep")
        dep_tx.status = "swept"
        dep_tx.swept_at = timezone.now()
        dep_tx.save(update_fields=["status", "swept_at"])
        return True

    gas_price    = w3.eth.gas_price
    gas_limit    = 100_000
    gas_cost_wei = gas_price * gas_limit

    # Fund deposit address with BNB for gas if needed
    bnb_balance = w3.eth.get_balance(deposit_addr_checksum)
    if bnb_balance < gas_cost_wei:
        needed = gas_cost_wei - bnb_balance + Web3.to_wei(0.0001, "ether")  # tiny buffer
        treasury_acct = w3.eth.account.from_key(treasury_key)
        nonce = w3.eth.get_transaction_count(treasury_acct.address)
        fund_tx = {
            "to":       deposit_addr_checksum,
            "value":    needed,
            "gas":      21000,
            "gasPrice": gas_price,
            "nonce":    nonce,
            "chainId":  56,
        }
        signed_fund = w3.eth.account.sign_transaction(fund_tx, treasury_key)
        fund_hash   = w3.eth.send_raw_transaction(signed_fund.rawTransaction)
        w3.eth.wait_for_transaction_receipt(fund_hash, timeout=60)
        logger.info(f"[sweeper] Funded {deposit_addr_checksum} for gas: {fund_hash.hex()}")

    # Build token transfer from deposit → treasury
    deposit_account = w3.eth.account.from_key(private_key_hex)
    nonce           = w3.eth.get_transaction_count(deposit_addr_checksum)

    tx = contract.functions.transfer(
        Web3.to_checksum_address(treasury),
        balance,
    ).build_transaction({
        "chainId":  56,
        "gas":      gas_limit,
        "gasPrice": gas_price,
        "nonce":    nonce,
    })

    signed  = w3.eth.account.sign_transaction(tx, private_key_hex)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

    if receipt.status == 1:
        dep_tx.status       = "swept"
        dep_tx.swept_at     = timezone.now()
        dep_tx.sweep_tx_hash = tx_hash.hex()
        dep_tx.save(update_fields=["status", "swept_at", "sweep_tx_hash"])
        logger.info(f"[sweeper] BEP-20 sweep success → {tx_hash.hex()}")
        return True
    else:
        dep_tx.status = "sweep_failed"
        dep_tx.save(update_fields=["status"])
        logger.error(f"[sweeper] BEP-20 sweep FAILED for deposit {dep_tx.id}")
        return False


def sweep_solana(dep_tx: DepositTransaction) -> bool:
    """
    Transfer SPL token balance from user deposit wallet → Solana treasury.
    """
    try:
        from solders.keypair import Keypair
        from solders.pubkey import Pubkey
        import base64 as b64
    except ImportError:
        logger.error("[sweeper] solders not installed")
        return False

    try:
        import httpx
    except ImportError:
        import requests as httpx

    rpc_url      = getattr(settings, "SOL_RPC_URL", "https://api.mainnet-beta.solana.com")
    treasury_b58 = getattr(settings, "SOL_TREASURY_ADDRESS", "")
    if not treasury_b58:
        logger.error("[sweeper] SOL_TREASURY_ADDRESS not set")
        return False

    deposit_obj = dep_tx.deposit_address
    token       = dep_tx.token
    mint_addr   = SOLANA_MINT_ADDRESSES[token]()

    # Reconstruct keypair
    secret_b64  = decrypt_secret(deposit_obj.encrypted_keypair)
    secret_bytes = b64.b64decode(secret_b64)
    kp           = Keypair.from_bytes(secret_bytes)

    def _rpc(method, params):
        resp = httpx.post(
            rpc_url,
            json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
            timeout=15,
        )
        return resp.json()

    # Get ATA of deposit wallet
    deposit_pubkey = str(kp.pubkey())
    ata_res = _rpc("getTokenAccountsByOwner", [
        deposit_pubkey,
        {"mint": mint_addr},
        {"encoding": "jsonParsed"},
    ])
    result = ata_res.get("result", {})
    if not result or not result.get("value"):
        logger.info(f"[sweeper] No Solana ATA for {deposit_pubkey} — nothing to sweep")
        dep_tx.status = "swept"
        dep_tx.swept_at = timezone.now()
        dep_tx.save(update_fields=["status", "swept_at"])
        return True

    ata_address = result["value"][0]["pubkey"]
    raw_balance = int(result["value"][0]["account"]["data"]["parsed"]["info"]["tokenAmount"]["amount"])

    if raw_balance == 0:
        dep_tx.status = "swept"
        dep_tx.swept_at = timezone.now()
        dep_tx.save(update_fields=["status", "swept_at"])
        return True

    # Use Solana's spl-token transfer via RPC (simplified — in production use solana-py or anchor)
    # NOTE: A more robust implementation would use solana-py's Transaction builder.
    # This sends via the Solana CLI-equivalent JSON-RPC calls.
    logger.info(
        f"[sweeper] Solana sweep queued for {deposit_pubkey} → {treasury_b58} "
        f"({raw_balance} raw {token}). Implement spl-token transfer with solana-py."
    )
    # Mark as sweep_pending for now; a Celery task or advanced implementation can complete this
    dep_tx.status = "sweep_pending"
    dep_tx.save(update_fields=["status"])
    return False  # Will be retried


# ─────────────────────────────────────────────────────────────────────────────
# SWEEP RUNNER  — called by the same cron endpoint
# ─────────────────────────────────────────────────────────────────────────────

def run_sweeper() -> dict:
    """Process all credited-but-not-yet-swept deposits."""
    if not getattr(settings, "AUTO_BLOCKCHAIN_SCAN_ENABLED", True):
        logger.info("[scanner] run_sweeper skipped — AUTO_BLOCKCHAIN_SCAN_ENABLED is False (manual payments mode).")
        return {"status": "disabled", "reason": "AUTO_BLOCKCHAIN_SCAN_ENABLED is False — payments are manual."}

    pending = DepositTransaction.objects.filter(status="credited").select_related(
        "deposit_address", "deposit_address__user", "user"
    )

    swept, failed = 0, 0
    for dep_tx in pending:
        dep_tx.status = "sweep_pending"
        dep_tx.save(update_fields=["status"])

        try:
            if dep_tx.network == "bep20":
                ok = sweep_bep20(dep_tx)
            elif dep_tx.network == "solana":
                ok = sweep_solana(dep_tx)
            else:
                ok = False

            if ok:
                swept += 1
            else:
                failed += 1
        except Exception as e:
            logger.error(f"[sweeper] Unhandled error for deposit {dep_tx.id}: {e}")
            dep_tx.status = "sweep_failed"
            dep_tx.save(update_fields=["status"])
            failed += 1

    return {"swept": swept, "failed": failed}
