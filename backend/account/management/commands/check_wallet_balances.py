"""
Management command: check_wallet_balances
==========================================
Checks LIVE on-chain USDT/USDC balances for user deposit wallets.
Queries BSC and Solana RPCs directly — shows what's actually sitting
in the wallet right now, whether the scanner has detected it or not.

Usage:
    # All users
    python manage.py check_wallet_balances

    # One user
    python manage.py check_wallet_balances --email user@example.com

    # Only BSC wallets
    python manage.py check_wallet_balances --network bep20

    # Only wallets that have a non-zero balance
    python manage.py check_wallet_balances --nonzero
"""

from decimal import Decimal
from django.conf import settings
from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model

from account.models import UserDepositAddress, DepositTransaction
from account.crypto_utils import BEP20_TOKEN_CONTRACTS, SOLANA_MINT_ADDRESSES, ERC20_ABI

User = get_user_model()

STABLECOIN_DECIMALS_BEP20  = 18
STABLECOIN_DECIMALS_SOLANA = 6


# ─────────────────────────────────────────────────────────────────────────────
# BEP-20 live balance
# ─────────────────────────────────────────────────────────────────────────────

def _bep20_balance(address: str) -> dict:
    """Returns {USDT: Decimal, USDC: Decimal, BNB: Decimal} for a BSC address."""
    try:
        from web3 import Web3
    except ImportError:
        return {"error": "web3 not installed"}

    rpc_url = getattr(settings, "BSC_RPC_URL", "https://bsc-dataseed.binance.org/")
    w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": 15}))

    if not w3.is_connected():
        return {"error": "BSC RPC not reachable"}

    checksum = Web3.to_checksum_address(address)
    result = {}

    # Native BNB balance
    try:
        bnb_wei = w3.eth.get_balance(checksum)
        result["BNB"] = Decimal(str(w3.from_wei(bnb_wei, "ether")))
    except Exception as e:
        result["BNB"] = f"error: {e}"

    # USDT and USDC token balances
    for token in ("USDT", "USDC"):
        try:
            contract_addr = BEP20_TOKEN_CONTRACTS[token]()
            contract = w3.eth.contract(
                address=Web3.to_checksum_address(contract_addr),
                abi=ERC20_ABI,
            )
            raw = contract.functions.balanceOf(checksum).call()
            result[token] = Decimal(raw) / Decimal(10 ** STABLECOIN_DECIMALS_BEP20)
        except Exception as e:
            result[token] = f"error: {e}"

    return result


# ─────────────────────────────────────────────────────────────────────────────
# Solana live balance
# ─────────────────────────────────────────────────────────────────────────────

def _solana_balance(address: str) -> dict:
    """Returns {USDT: Decimal, USDC: Decimal, SOL: Decimal} for a Solana address."""
    try:
        import httpx
        def _post(payload):
            return httpx.post(rpc_url, json=payload, timeout=15).json()
    except ImportError:
        try:
            import requests
            def _post(payload):
                return requests.post(rpc_url, json=payload, timeout=15).json()
        except ImportError:
            return {"error": "httpx or requests not installed"}

    rpc_url = getattr(settings, "SOL_RPC_URL", "https://api.mainnet-beta.solana.com")
    result = {}

    # Native SOL balance
    try:
        resp = _post({
            "jsonrpc": "2.0", "id": 1,
            "method": "getBalance",
            "params": [address],
        })
        lamports = resp.get("result", {}).get("value", 0)
        result["SOL"] = Decimal(lamports) / Decimal(10 ** 9)
    except Exception as e:
        result["SOL"] = f"error: {e}"

    # USDT and USDC SPL token balances
    for token in ("USDT", "USDC"):
        try:
            mint_addr = SOLANA_MINT_ADDRESSES[token]()
            resp = _post({
                "jsonrpc": "2.0", "id": 1,
                "method": "getTokenAccountsByOwner",
                "params": [
                    address,
                    {"mint": mint_addr},
                    {"encoding": "jsonParsed"},
                ],
            })
            accounts = resp.get("result", {}).get("value", [])
            if not accounts:
                result[token] = Decimal("0")
            else:
                total = Decimal("0")
                for acc in accounts:
                    raw = acc["account"]["data"]["parsed"]["info"]["tokenAmount"]["amount"]
                    total += Decimal(raw) / Decimal(10 ** STABLECOIN_DECIMALS_SOLANA)
                result[token] = total
        except Exception as e:
            result[token] = f"error: {e}"

    return result


# ─────────────────────────────────────────────────────────────────────────────
# Command
# ─────────────────────────────────────────────────────────────────────────────

class Command(BaseCommand):
    help = "Check live on-chain USDT/USDC balances for user deposit wallets."

    def add_arguments(self, parser):
        parser.add_argument("--email",   type=str, help="Filter by user email")
        parser.add_argument("--network", type=str, choices=["bep20", "solana"], help="Filter by network")
        parser.add_argument("--nonzero", action="store_true", help="Only show wallets with a non-zero balance")

    def handle(self, *args, **options):
        email   = options.get("email")
        network = options.get("network")
        nonzero = options.get("nonzero")

        qs = UserDepositAddress.objects.select_related("user")

        if email:
            try:
                target_user = User.objects.get(email__iexact=email)
            except User.DoesNotExist:
                self.stderr.write(self.style.ERROR(f"No user found with email: {email}"))
                return
            qs = qs.filter(user=target_user)
            if not qs.exists():
                self.stderr.write(self.style.WARNING(
                    f"User {email} exists but has no deposit addresses assigned yet."
                ))
                return
        else:
            qs = qs.filter(is_active=True)

        if network:
            qs = qs.filter(network=network)

        if not qs.exists():
            self.stderr.write(self.style.WARNING("No deposit addresses found for those filters."))
            return

        self.stdout.write(f"\nChecking {qs.count()} wallet(s) on-chain...\n")

        grand_usdt = Decimal("0")
        grand_usdc = Decimal("0")

        for addr_obj in qs:
            user    = addr_obj.user
            address = addr_obj.address
            net     = addr_obj.network

            # Fetch live balances
            if net == "bep20":
                balances = _bep20_balance(address)
                native_symbol = "BNB"
            else:
                balances = _solana_balance(address)
                native_symbol = "SOL"

            usdt = balances.get("USDT", Decimal("0"))
            usdc = balances.get("USDC", Decimal("0"))
            native = balances.get(native_symbol, Decimal("0"))

            # Skip zero wallets if --nonzero flag set
            if nonzero:
                try:
                    if usdt == Decimal("0") and usdc == Decimal("0"):
                        continue
                except Exception:
                    pass

            # Count DB deposits for this address
            db_tx_count = DepositTransaction.objects.filter(deposit_address=addr_obj).count()
            pending_db  = DepositTransaction.objects.filter(
                deposit_address=addr_obj, status__in=["detected", "sweep_pending", "sweep_failed"]
            ).count()

            self.stdout.write("─" * 60)
            self.stdout.write(f"  User    : {user.email}")
            self.stdout.write(f"  Network : {net.upper()}")
            self.stdout.write(f"  Address : {address}")
            self.stdout.write(f"  ── Live on-chain balances ──")
            self.stdout.write(f"  USDT    : {usdt}")
            self.stdout.write(f"  USDC    : {usdc}")
            self.stdout.write(f"  {native_symbol:<7} : {native}  (gas)")
            self.stdout.write(f"  ── DB records ──")
            self.stdout.write(f"  Total deposits recorded : {db_tx_count}")
            if pending_db:
                self.stdout.write(
                    self.style.WARNING(f"  ⚠ Pending/failed sweeps  : {pending_db}")
                )

            # Warn if on-chain balance is non-zero but not swept
            try:
                if usdt > Decimal("0") or usdc > Decimal("0"):
                    self.stdout.write(
                        self.style.WARNING(
                            f"  ⚠ Non-zero balance on-chain — funds may not be swept yet."
                        )
                    )
                    grand_usdt += usdt if isinstance(usdt, Decimal) else Decimal("0")
                    grand_usdc += usdc if isinstance(usdc, Decimal) else Decimal("0")
            except Exception:
                pass

        self.stdout.write("\n" + "═" * 60)
        self.stdout.write(f"  TOTAL unsswept USDT across all wallets : {grand_usdt}")
        self.stdout.write(f"  TOTAL unsswept USDC across all wallets : {grand_usdc}")
        self.stdout.write("═" * 60 + "\n")



# # Specific user — only their wallets
# python manage.py check_wallet_balances --email a@gmail.com

# # User doesn't exist
# → Error: No user found with email: a@gmail.com

# # User exists but no wallet assigned yet
# → Warning: User a@gmail.com exists but has no deposit addresses assigned yet.

# # All users (no --email flag)
# python manage.py check_wallet_balances

# # Specific user, specific network
# python manage.py check_wallet_balances --email a@gmail.com --network bep20