"""
deposit_views.py
================
Views for the unique-deposit-address-per-user system.

Endpoints:
  GET  /api/v1/payments/deposit/address/?network=bep20&token=USDT
       → Returns (or creates) the user's unique deposit address

  GET  /api/v1/payments/deposit/history/
       → Paginated list of the user's deposit transactions

  GET  /api/v1/payments/deposit/scan/
       → CRON ENDPOINT — hit every 10 s from your cron-job (no auth required
         when CRON_SECRET header matches settings.CRON_SECRET)

  GET  /api/v1/payments/deposit/status/
       → Scan state (admin/debug info)
"""

import logging
from decimal import Decimal

from django.conf import settings
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import UserDepositAddress, DepositTransaction, BlockScanState
from .crypto_utils import (
    _bep20_index_lock,
    _get_next_bep20_index_locked,
    generate_bep20_wallet,
    generate_solana_wallet,
    get_next_bep20_index,
)

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

VALID_NETWORKS = ["bep20", "solana"]
VALID_TOKENS   = ["USDT", "USDC"]

# Tokens supported per network (BEP-20 only offers USDT)
NETWORK_TOKENS = {
    "bep20":  ["USDT"],
    "solana": ["USDT", "USDC"],
}

NETWORK_LABELS = {
    "bep20":  "BEP-20 (Binance Smart Chain)",
    "solana": "Solana",
}
TOKEN_LABELS = {
    "USDT": "Tether USD",
    "USDC": "USD Coin",
}


def _get_or_create_deposit_address(user, network: str, token: str) -> UserDepositAddress:
    """
    Fetch the existing deposit address for this user+network+token,
    or generate a fresh one and persist it.

    BEP-20 note: On BSC, one wallet address receives ALL tokens (USDT, USDC, etc).
    So we derive ONE wallet per user and reuse it for every BEP-20 token.
    This completely eliminates the UNIQUE constraint collision that happened
    when USDT and USDC tried to generate separate wallets with the same index.
    """
    from django.db import IntegrityError, transaction
    try:
        return UserDepositAddress.objects.get(user=user, network=network, token=token)
    except UserDepositAddress.DoesNotExist:
        pass

    if network == "bep20":
        with _bep20_index_lock:
            # Re-check inside the lock — another thread may have just created it.
            try:
                return UserDepositAddress.objects.get(user=user, network=network, token=token)
            except UserDepositAddress.DoesNotExist:
                pass

            # Check if this user already has ANY bep20 address (another token).
            # If so, reuse the same wallet — one BSC address holds all tokens.
            existing_bep20 = (
                UserDepositAddress.objects
                .filter(user=user, network="bep20")
                .first()
            )

            if existing_bep20:
                # Reuse the same wallet for this token.
                obj = UserDepositAddress.objects.create(
                    user                  = user,
                    network               = network,
                    token                 = token,
                    address               = existing_bep20.address,
                    encrypted_private_key = existing_bep20.encrypted_private_key,
                    derivation_index      = existing_bep20.derivation_index,
                )
            else:
                # First BEP-20 token for this user — generate a new wallet.
                idx    = _get_next_bep20_index_locked()  # already holding the lock
                wallet = generate_bep20_wallet(idx)
                obj    = UserDepositAddress.objects.create(
                    user                  = user,
                    network               = network,
                    token                 = token,
                    address               = wallet["address"],
                    encrypted_private_key = wallet["encrypted_private_key"],
                    derivation_index      = wallet["derivation_index"],
                )

    elif network == "solana":
        wallet = generate_solana_wallet()
        obj    = UserDepositAddress.objects.create(
            user               = user,
            network            = network,
            token              = token,
            address            = wallet["address"],
            encrypted_keypair  = wallet["encrypted_keypair"],
        )
    else:
        raise ValueError(f"Unsupported network: {network}")

    logger.info(
        f"[deposit] New {token} {network} address created for {user.email}: {obj.address}"
    )
    return obj


# ─────────────────────────────────────────────────────────────────────────────
# VIEWS
# ─────────────────────────────────────────────────────────────────────────────

class UserDepositAddressView(APIView):
    """
    GET /api/v1/payments/deposit/address/
    Query params: network (bep20|solana), token (USDT|USDC)

    Returns the user's unique deposit address for the given network+token,
    creating it on first request.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        network = request.query_params.get("network", "bep20").lower().strip()
        token   = request.query_params.get("token", "USDT").upper().strip()

        if network not in VALID_NETWORKS:
            return Response(
                {"error": f"Invalid network. Choose from: {VALID_NETWORKS}"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if token not in VALID_TOKENS:
            return Response(
                {"error": f"Invalid token. Choose from: {VALID_TOKENS}"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            addr_obj = _get_or_create_deposit_address(request.user, network, token)
        except Exception as e:
            logger.error(f"[deposit] Address generation failed for {request.user.email}: {e}")
            return Response(
                {"error": "Could not generate deposit address. Please try again later."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        # Pending balance (detected but not yet confirmed on-chain)
        pending = DepositTransaction.objects.filter(
            deposit_address=addr_obj,
            status="detected",
        ).count()

        # Recent deposits for this address
        recent = list(
            DepositTransaction.objects.filter(deposit_address=addr_obj)
            .order_by("-detected_at")
            .values("tx_hash", "amount", "token", "status", "detected_at", "credited_at", "credits_added")[:5]
        )

        return Response({
            "address":       addr_obj.address,
            "network":       network,
            "network_label": NETWORK_LABELS[network],
            "token":         token,
            "token_label":   TOKEN_LABELS[token],
            "note": (
                f"Send only {token} on the {NETWORK_LABELS[network]} network to this address. "
                "Funds are credited automatically within ~30 seconds of confirmation."
            ),
            "pending_deposits":  pending,
            "recent_deposits":   recent,
        })


class UserDepositHistoryView(APIView):
    """
    GET /api/v1/payments/deposit/history/
    Paginated list of all deposit transactions for the authenticated user.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        page      = max(1, int(request.query_params.get("page", 1)))
        page_size = min(50, max(1, int(request.query_params.get("page_size", 20))))
        offset    = (page - 1) * page_size

        qs    = DepositTransaction.objects.filter(user=request.user).order_by("-detected_at")
        total = qs.count()
        items = list(qs.values(
            "id", "tx_hash", "network", "token",
            "amount", "amount_usd", "credits_added",
            "status", "block_number",
            "detected_at", "credited_at", "swept_at", "sweep_tx_hash",
        )[offset: offset + page_size])

        return Response({
            "results":     items,
            "count":       total,
            "total_pages": max(1, -(-total // page_size)),
            "page":        page,
            "page_size":   page_size,
        })


class BlockchainScanView(APIView):
    """
    GET /api/v1/payments/deposit/scan/

    CRON ENDPOINT — hit every 10 seconds.
    Protected by a simple secret header: X-Cron-Secret: <settings.CRON_SECRET>

    What it does:
      1. Scans BSC for new USDT/USDC transfers to user deposit addresses.
      2. Scans Solana for new SPL token transfers.
      3. Credits user balances for any new deposits.
      4. Sweeps funded deposit wallets to the master treasury.
    """
    permission_classes = [permissions.AllowAny]

    def _is_authorized(self, request) -> bool:
        cron_secret = getattr(settings, "CRON_SECRET", "")
        if not cron_secret:
            remote_ip = (
                request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[0].strip()
                or request.META.get("REMOTE_ADDR", "")
            )
            return remote_ip in ("127.0.0.1", "::1", "localhost")
        provided = (
            request.headers.get("X-Cron-Secret", "")
            or request.query_params.get("secret", "")
        )
        return provided == cron_secret

    def get(self, request):
        if not self._is_authorized(request):
            return Response({"error": "Unauthorized"}, status=status.HTTP_401_UNAUTHORIZED)

        from .blockchain_scanner import scan_bep20, scan_solana, run_sweeper

        started_at = timezone.now()
        results    = {}

        try:
            results["bep20"]  = scan_bep20()
        except Exception as e:
            logger.error(f"[cron] BEP-20 scan crashed: {e}")
            results["bep20"]  = {"error": str(e)}

        try:
            results["solana"] = scan_solana()
        except Exception as e:
            logger.error(f"[cron] Solana scan crashed: {e}")
            results["solana"] = {"error": str(e)}

        try:
            results["sweep"]  = run_sweeper()
        except Exception as e:
            logger.error(f"[cron] Sweeper crashed: {e}")
            results["sweep"]  = {"error": str(e)}

        elapsed = (timezone.now() - started_at).total_seconds()

        return Response({
            "status":     "ok",
            "elapsed_s":  round(elapsed, 3),
            "results":    results,
            "scanned_at": started_at.isoformat(),
        })


class BlockchainScanBEP20View(APIView):
    """
    GET /api/v1/payments/deposit/scan/bep20/

    CRON ENDPOINT — scan BSC only.
    Call this every 10–30 s from your cron job.
    Header required: X-Cron-Secret: <settings.CRON_SECRET>
    """
    permission_classes = [permissions.AllowAny]

    def _is_authorized(self, request) -> bool:
        cron_secret = getattr(settings, "CRON_SECRET", "")
        if not cron_secret:
            remote_ip = (
                request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[0].strip()
                or request.META.get("REMOTE_ADDR", "")
            )
            return remote_ip in ("127.0.0.1", "::1", "localhost")
        provided = (
            request.headers.get("X-Cron-Secret", "")
            or request.query_params.get("secret", "")
        )
        return provided == cron_secret

    def get(self, request):
        if not self._is_authorized(request):
            return Response({"error": "Unauthorized"}, status=status.HTTP_401_UNAUTHORIZED)

        from .blockchain_scanner import scan_bep20

        started_at = timezone.now()
        try:
            result = scan_bep20()
        except Exception as e:
            logger.error(f"[cron/bep20] scan crashed: {e}")
            result = {"error": str(e)}

        elapsed = (timezone.now() - started_at).total_seconds()
        return Response({
            "status":     "ok",
            "elapsed_s":  round(elapsed, 3),
            "result":     result,
            "scanned_at": started_at.isoformat(),
        })


class BlockchainScanSolanaView(APIView):
    """
    GET /api/v1/payments/deposit/scan/solana/

    CRON ENDPOINT — scan Solana only.
    Call this every 10–30 s from your cron job.
    Header required: X-Cron-Secret: <settings.CRON_SECRET>
    """
    permission_classes = [permissions.AllowAny]

    def _is_authorized(self, request) -> bool:
        cron_secret = getattr(settings, "CRON_SECRET", "")
        if not cron_secret:
            remote_ip = (
                request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[0].strip()
                or request.META.get("REMOTE_ADDR", "")
            )
            return remote_ip in ("127.0.0.1", "::1", "localhost")
        provided = (
            request.headers.get("X-Cron-Secret", "")
            or request.query_params.get("secret", "")
        )
        return provided == cron_secret

    def get(self, request):
        if not self._is_authorized(request):
            return Response({"error": "Unauthorized"}, status=status.HTTP_401_UNAUTHORIZED)

        from .blockchain_scanner import scan_solana

        started_at = timezone.now()
        try:
            result = scan_solana()
        except Exception as e:
            logger.error(f"[cron/solana] scan crashed: {e}")
            result = {"error": str(e)}

        elapsed = (timezone.now() - started_at).total_seconds()
        return Response({
            "status":     "ok",
            "elapsed_s":  round(elapsed, 3),
            "result":     result,
            "scanned_at": started_at.isoformat(),
        })


class BlockchainSweeperView(APIView):
    """
    GET /api/v1/payments/deposit/scan/sweep/

    CRON ENDPOINT — run the treasury sweeper only.
    Call this less frequently, e.g. every 60 s.
    Header required: X-Cron-Secret: <settings.CRON_SECRET>
    """
    permission_classes = [permissions.AllowAny]

    def _is_authorized(self, request) -> bool:
        cron_secret = getattr(settings, "CRON_SECRET", "")
        if not cron_secret:
            remote_ip = (
                request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[0].strip()
                or request.META.get("REMOTE_ADDR", "")
            )
            return remote_ip in ("127.0.0.1", "::1", "localhost")
        provided = (
            request.headers.get("X-Cron-Secret", "")
            or request.query_params.get("secret", "")
        )
        return provided == cron_secret

    def get(self, request):
        if not self._is_authorized(request):
            return Response({"error": "Unauthorized"}, status=status.HTTP_401_UNAUTHORIZED)

        from .blockchain_scanner import run_sweeper

        started_at = timezone.now()
        try:
            result = run_sweeper()
        except Exception as e:
            logger.error(f"[cron/sweep] sweeper crashed: {e}")
            result = {"error": str(e)}

        elapsed = (timezone.now() - started_at).total_seconds()
        return Response({
            "status":     "ok",
            "elapsed_s":  round(elapsed, 3),
            "result":     result,
            "scanned_at": started_at.isoformat(),
        })


class DepositScanStatusView(APIView):
    """
    GET /api/v1/payments/deposit/status/
    Returns current scan state for each network (admin/debug).
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if not (request.user.is_staff or request.user.is_superuser):
            return Response({"error": "Admin only"}, status=status.HTTP_403_FORBIDDEN)

        states = list(BlockScanState.objects.values())
        return Response({"scan_states": states})


class AllDepositAddressesView(APIView):
    """
    GET /api/v1/payments/deposit/my-addresses/
    Returns all deposit addresses for the authenticated user across all networks.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        addresses = []
        for network in VALID_NETWORKS:
            for token in NETWORK_TOKENS[network]:
                try:
                    obj = _get_or_create_deposit_address(request.user, network, token)
                    addresses.append({
                        "network":       network,
                        "network_label": NETWORK_LABELS[network],
                        "token":         token,
                        "address":       obj.address,
                        "created_at":    obj.created_at.isoformat(),
                    })
                except Exception as e:
                    logger.error(f"[deposit] Failed to get {token}/{network} for {request.user.email}: {e}")
                    addresses.append({
                        "network": network,
                        "token":   token,
                        "error":   "Address unavailable",
                    })

        return Response({"deposit_addresses": addresses})