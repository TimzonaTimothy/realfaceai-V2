import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/credit_pack.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pro_layout.dart';
import '../../widgets/shared_widgets.dart';
import '../../utils/error_handler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BILLING SCREEN
// Manual crypto payment flow:
//   1. User taps Buy on a pack, picks the crypto network in the checkout
//      dialog → POST /auth/payments/create/  (a blocking "Creating payment…"
//      overlay is shown while waiting)
//   2. Server returns the payment id + the wallet address (stored on the
//      payment, so reopening the instructions always shows the same one)
//   3. User sends funds off-app, then uploads proof via
//      POST /auth/payments/<id>/proof/. The server writes the image to disk
//      before replying, so "Proof received" means it really is there.
//   4. History shows, per payment, whether proof was sent / received, and
//      lets the user reopen the instructions or re-upload.
//   5. An admin confirms in Django admin; this screen polls
//      /auth/<id>/status/ until it flips to "confirmed".
// ─────────────────────────────────────────────────────────────────────────────

const int _kMaxProofBytes = 10 * 1024 * 1024; // keep in sync with the server

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

String _fmtDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso.length >= 16 ? iso.substring(0, 16) : iso;
  final l = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<CreditPack> _packs = [];
  List<Payment> _history = [];
  int _historyPage = 1;
  int _historyTotalPages = 1;
  int _historyTotal = 0;
  bool _loading = true;

  // Currency selection (crypto only — admin-managed list from the backend)
  List<Map<String, String>> _cryptoCurrencies = [];
  String _selectedCurrency = 'usdttrc20';

  // True while POST /payments/create/ is in flight (shows a blocking overlay
  // so "Continue" never looks like it did nothing).
  bool _creating = false;

  // Pending payment tracking
  String? _pendingPaymentId;
  String? _pollingPaymentId;
  Timer? _paymentPollTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _paymentPollTimer?.cancel();
    super.dispose();
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color ?? AppColors.danger,
    ));
  }

  Payment? _historyEntry(String? id) {
    if (id == null) return null;
    for (final p in _history) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ── Load credit packs + payment history + currencies ─────────────────────
  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getCreditPacks(),
        ApiService.instance.getPaymentHistory(page: _historyPage),
        ApiService.instance.getCurrencies(),
      ]);

      final packs = results[0] as List<dynamic>;
      final historyData = results[1] as Map<String, dynamic>;
      final currencies = results[2] as Map<String, dynamic>;

      final rawCrypto = (currencies['crypto'] as List? ?? [])
          .map((c) => {
                'id': (c['id'] as String? ?? ''),
                'label': (c['label'] as String? ?? ''),
              })
          .where((c) => c['id']!.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _packs = packs
            .map((j) => CreditPack.fromJson(j as Map<String, dynamic>))
            .toList();
        _history = (historyData['results'] as List? ?? [])
            .map((j) => Payment.fromJson(j as Map<String, dynamic>))
            .toList();
        _historyTotalPages = historyData['total_pages'] ?? 1;
        _historyTotal = historyData['count'] ?? 0;
        _cryptoCurrencies = rawCrypto;

        // Auto-select first currency if current selection no longer exists
        if (_cryptoCurrencies.isNotEmpty &&
            !_cryptoCurrencies.any((c) => c['id'] == _selectedCurrency)) {
          _selectedCurrency = _cryptoCurrencies.first['id']!;
        }

        _loading = false;
      });
      _syncPendingWithHistory();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// After an app restart (or when the create response never arrived) the
  /// newest pending payment is picked up from history, so the pending bar,
  /// "Upload proof" and polling all come back.
  void _syncPendingWithHistory() {
    if (_historyPage != 1) return;

    final tracked = _historyEntry(_pendingPaymentId);
    if (tracked != null &&
        (tracked.status == 'failed' || tracked.status == 'expired')) {
      _paymentPollTimer?.cancel();
      _pollingPaymentId = null;
      setState(() => _pendingPaymentId = null);
    }

    if (_pendingPaymentId == null) {
      for (final p in _history) {
        if (p.isPending) {
          setState(() => _pendingPaymentId = p.id);
          _startPaymentPolling(p.id);
          break;
        }
      }
    }
  }

  // ── Buy a pack ─────────────────────────────────────────────────────────────
  Future<void> _buyPack(CreditPack pack) async {
    if (_creating) return;
    if (_cryptoCurrencies.isEmpty) {
      _snack('Payment methods are unavailable right now. Refresh and try again.');
      return;
    }

    final currency = await showDialog<String>(
      context: context,
      builder: (_) => _CheckoutDialog(
        pack: pack,
        currencies: _cryptoCurrencies,
        initial: _selectedCurrency,
      ),
    );
    if (currency == null || !mounted) return;
    setState(() {
      _selectedCurrency = currency;
      _creating = true;
    });

    Map<String, dynamic>? result;
    Object? error;
    try {
      result = await ApiService.instance.createPayment(
        packId: pack.id,
        currency: currency,
      );
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _creating = false);

    final sc = result?['statusCode'] as int? ?? 0;

    // No usable answer (timeout, dropped connection, hosting error page).
    // The payment may still have been created — look for it before
    // telling the user it failed, so they don't create duplicates.
    if (error != null || result == null || sc >= 500 || sc == 0) {
      final recovered = await _findRecentPending(pack.id, currency);
      if (!mounted) return;
      if (recovered != null) {
        await _openInstructions(recovered.id);
        return;
      }
      _snack(error is TimeoutException
          ? 'The server is taking too long to respond. Please try again.'
          : error != null
              ? ErrorHandler.sanitize(error)
              : (result?['error']?.toString() ??
                  'Payment failed. Please try again.'));
      return;
    }

    if (sc != 200 && sc != 201) {
      _snack(result['error']?.toString() ?? 'Payment failed. Try again.');
      return;
    }

    final paymentId = result['payment_id']?.toString() ?? '';
    if (paymentId.isEmpty) {
      _snack('Unexpected server response. Please refresh.');
      return;
    }

    setState(() => _pendingPaymentId = paymentId);
    _startPaymentPolling(paymentId);
    _loadData(); // show the new payment in history straight away

    await _showPendingInstructionsDialog(result);
  }

  /// Newest pending payment for this pack + network created in the last
  /// 15 minutes, or null.
  Future<Payment?> _findRecentPending(String packId, String currency) async {
    try {
      final data = await ApiService.instance
          .getPaymentHistory(page: 1)
          .timeout(const Duration(seconds: 20));
      final list = (data['results'] as List? ?? [])
          .map((j) => Payment.fromJson(j as Map<String, dynamic>))
          .toList();
      final cutoff =
          DateTime.now().toUtc().subtract(const Duration(minutes: 15));
      for (final p in list) {
        if (!p.isPending || p.packId != packId || p.currency != currency) {
          continue;
        }
        final created = DateTime.tryParse(p.createdAt);
        if (created != null && created.toUtc().isAfter(cutoff)) {
          _loadData();
          return p;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetches the stored instructions for a payment and shows them.
  Future<void> _openInstructions(String paymentId) async {
    Map<String, dynamic> result;
    try {
      result = await ApiService.instance.getPaymentStatus(paymentId);
    } catch (e) {
      _snack(e is TimeoutException
          ? 'The server is taking too long to respond. Please try again.'
          : ErrorHandler.sanitize(e));
      return;
    }
    if (!mounted) return;
    if ((result['statusCode'] as int? ?? 0) != 200) {
      _snack(result['error']?.toString() ?? 'Could not load payment details.');
      return;
    }
    final st = result['status']?.toString() ?? '';
    if (st == 'waiting' || st == 'confirming') {
      setState(() => _pendingPaymentId = paymentId);
      _startPaymentPolling(paymentId);
    }
    await _showPendingInstructionsDialog(result);
  }

  // ── Poll for payment status ────────────────────────────────────────────────
  void _startPaymentPolling(String paymentId) {
    if (_pollingPaymentId == paymentId && _paymentPollTimer != null) return;
    _paymentPollTimer?.cancel();
    _pollingPaymentId = paymentId;
    // Confirmed manually by an admin — poll every 30s to avoid hammering the server
    _paymentPollTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final status = await ApiService.instance.getPaymentStatus(paymentId);
        if (!mounted) return;
        final st = status['status'];
        if (st == 'confirmed') {
          _handlePaymentConfirmed(
            paymentId: paymentId,
            credits: (status['credits'] as num?)?.toInt() ?? 0,
            balance: (status['credits_balance'] as num?)?.toDouble() ?? 0,
          );
        } else if (st == 'failed' || st == 'expired') {
          _paymentPollTimer?.cancel();
          _pollingPaymentId = null;
          setState(() => _pendingPaymentId = null);
          _loadData();
        }
      } catch (_) {
        // network blip — try again on the next tick
      }
    });
  }

  void _handlePaymentConfirmed({
    required String paymentId,
    required int credits,
    required double balance,
  }) {
    _paymentPollTimer?.cancel();
    _pollingPaymentId = null;
    if (!mounted) return;
    context.read<AuthProvider>().updateCredits(balance);
    setState(() => _pendingPaymentId = null);
    _loadData();
    _showSuccessDialog(credits, balance);
  }

  void _showSuccessDialog(int creditsAdded, double newBalance) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.success),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 56),
            const SizedBox(height: 16),
            Text('Payment Confirmed!',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('+$creditsAdded credits added',
                style:
                    TextStyle(color: AppColors.success, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'Balance: ${CreditDisplay.toTime(newBalance)}  ·  '
              '${newBalance.toStringAsFixed(0)} cr',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Awesome!'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pending payment instructions dialog ────────────────────────────────────
  // `result` is the response of CreatePaymentView or PaymentStatusView —
  // both carry the stored wallet address, amount and proof_count.
  Future<void> _showPendingInstructionsDialog(
      Map<String, dynamic> result) async {
    final amountUsd = result['amount_usd']?.toString() ?? '';
    final currencyId =
        (result['currency'] as String? ?? _selectedCurrency).toLowerCase();
    final credits = result['credits']?.toString() ?? '';
    final paymentId = result['payment_id']?.toString() ?? '';
    final proofCount = (result['proof_count'] as num?)?.toInt() ?? 0;

    final walletAddr = result['wallet_address'] as String? ?? '';
    final walletLabel =
        result['wallet_label'] as String? ?? currencyId.toUpperCase();
    final walletNet = result['wallet_network'] as String? ?? currencyId;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.schedule_rounded,
                    color: AppColors.warning, size: 28),
                const SizedBox(width: 10),
                Text('Payment Pending',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 14),
              Text(
                'Send the exact amount to the wallet address below. '
                'Once we verify your transfer, your credits will be added '
                'and you\'ll receive a confirmation email.',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5),
              ),
              const SizedBox(height: 16),

              // ── Order summary ────────────────────────────────────────
              _InfoRow(label: 'Amount to send', value: '\$$amountUsd USD'),
              _InfoRow(
                  label: 'Network',
                  value: walletNet.isNotEmpty ? walletNet : walletLabel),
              _InfoRow(label: 'Credits', value: '$credits credits'),
              _InfoRow(label: 'Payment ID', value: paymentId),
              _InfoRow(
                  label: 'Proof',
                  value: proofCount == 0
                      ? 'Not sent yet'
                      : '$proofCount sent'),
              const SizedBox(height: 16),

              // ── Wallet address box ───────────────────────────────────
              Text(walletLabel,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        walletAddr.isNotEmpty
                            ? walletAddr
                            : 'Address not configured',
                        style: TextStyle(
                          color: walletAddr.isNotEmpty
                              ? AppColors.textPrimary
                              : AppColors.warning,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (walletAddr.isNotEmpty) _CopyButton(text: walletAddr),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Warning ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Send ONLY the exact amount on the correct network. '
                      'Wrong network = lost funds.',
                      style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.goldGlow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, color: AppColors.accent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can reopen these details any time from Payment '
                      'history. Quote your Payment ID in any support message.',
                      style: TextStyle(color: AppColors.accent, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
        actions: [
          Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_rounded, size: 16),
                  label: Text(proofCount == 0
                      ? 'Submit Payment Proof'
                      : 'View / Re-upload Proof'),
                  onPressed: () {
                    final pid = paymentId;
                    Navigator.of(context, rootNavigator: true).pop();
                    if (pid.isNotEmpty) _showPaymentProofDialog(pid);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: BorderSide(color: AppColors.warning),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(proofCount == 0
                      ? "I'll submit proof later"
                      : 'Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Submit / view payment proof dialog ─────────────────────────────────────
  Future<void> _showPaymentProofDialog(String paymentId) async {
    await showDialog(
      context: context,
      builder: (_) => _PaymentProofDialog(
        paymentId: paymentId,
        onSubmitted: () {
          if (mounted) _loadData();
        },
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  //
  //   Toolbar (balance · refresh)
  //   [pending-payment bar, only when a payment is waiting]
  //   ┌ Packs (compact table; Buy → checkout dialog picks network) ┐
  //   ├ Payment history (own scroll, pager) ───────────────────────┤
  //   └────────────────────────────────────────────────────────────┘

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              ProToolbar(
                icon: Icons.receipt_long_rounded,
                title: 'Billing',
                subtitle:
                    'Top up streaming time with crypto. Credits never expire.',
                actions: [
                  _BalanceTag(text: CreditDisplay.toTime(auth.credits)),
                  ProToolButton(
                    icon: Icons.refresh_rounded,
                    label: 'Refresh',
                    onPressed: _loading ? null : _loadData,
                  ),
                ],
              ),
              if (_pendingPaymentId != null) _pendingBar(),
              Expanded(
                child: _loading && _packs.isEmpty
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AppColors.cobalt, strokeWidth: 2))
                    : ProWorkspace(main: _mainColumn()),
              ),
            ],
          ),
          if (_creating) _creatingOverlay(),
        ],
      ),
    );
  }

  Widget _creatingOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          ModalBarrier(
              dismissible: false,
              color: Colors.black.withValues(alpha: 0.35)),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: AppColors.cobalt, strokeWidth: 2.2),
                  ),
                  const SizedBox(width: 14),
                  Text('Creating your payment…',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingBar() {
    final entry = _historyEntry(_pendingPaymentId);
    final String proofText;
    if (entry == null || !entry.hasProof) {
      proofText = 'Upload your proof of payment to speed up verification.';
    } else if (entry.proofNeedsRetry) {
      proofText = 'Your last proof upload didn\'t reach us — please re-upload.';
    } else {
      proofText = 'Proof received — awaiting confirmation.';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(28, 14, 28, 0),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.warningWash,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                color: AppColors.warning, strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Payment ${_pendingPaymentId!} pending. $proofText',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 14),
            label: const Text('Details'),
            onPressed: () => _openInstructions(_pendingPaymentId!),
            style: TextButton.styleFrom(foregroundColor: AppColors.cobalt),
          ),
          TextButton.icon(
            icon: const Icon(Icons.upload_rounded, size: 14),
            label: Text(entry != null && entry.hasProof
                ? 'Re-upload proof'
                : 'Upload proof'),
            onPressed: () => _showPaymentProofDialog(_pendingPaymentId!),
            style: TextButton.styleFrom(foregroundColor: AppColors.cobalt),
          ),
        ],
      ),
    );
  }

  // ── Main: packs table over history ────────────────────────────────────────
  Widget _mainColumn() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        // Ensure the history panel retains at least 160-260px so EmptyState or rows
        // never get crushed when window height is constrained.
        final minHistory = (maxH * 0.45).clamp(160.0, 260.0);
        final availableForPacks =
            (maxH - minHistory - 12.0).clamp(140.0, double.infinity);
        final idealPacks = _packs.length * 68.0 + 96.0;
        final packsHeight =
            idealPacks.clamp(140.0, availableForPacks.clamp(140.0, 360.0));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: packsHeight, child: _packsPanel()),
            const SizedBox(height: 16),
            Expanded(child: _historyPanel()),
          ],
        );
      },
    );
  }

  Widget _packsPanel() {
    // Phones: the 4-column table doesn't fit, so each pack becomes a
    // two-line row and the header hint is dropped.
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ProPanel(
      title: 'Credit packs',
      icon: Icons.inventory_2_rounded,
      scroll: false,
      padding: EdgeInsets.zero,
      trailing: compact
          ? null
          : Text(
              'Pick a pack, then choose your crypto network',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
      child: Column(
        children: [
          if (!compact) ...[
            const _TableHead(cells: [
              _HeadCell('Pack', flex: 4),
              _HeadCell('Streaming time', flex: 3),
              _HeadCell('Credits', flex: 2),
              _HeadCell('Price', flex: 2, right: true),
            ]),
            Divider(height: 1, color: AppColors.border),
          ],
          Expanded(
            child: _packs.isEmpty
                ? Center(
                    child: Text('No packs available',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)))
                : ListView.separated(
                    itemCount: _packs.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) => _PackRow(
                      pack: _packs[i],
                      compact: compact,
                      onBuy: _creating ? null : () => _buyPack(_packs[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _historyPanel() {
    return ProPanel(
      title: 'Payment history',
      icon: Icons.history_rounded,
      scroll: _history.isEmpty,
      padding: EdgeInsets.zero,
      trailing: Text(
        '$_historyTotal total',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
      ),
      child: _history.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'No payments yet',
              subtitle: 'Your payment history will appear here',
            )
          : Column(
              children: [
                const _TableHead(cells: [
                  _HeadCell('Pack', flex: 3),
                  _HeadCell('Amount', flex: 2),
                  _HeadCell('Time added', flex: 2),
                  _HeadCell('Proof · Status', flex: 5, right: true),
                ]),
                Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: ListView.separated(
                    itemCount: _history.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) {
                      final p = _history[i];
                      return _PaymentRow(
                        payment: p,
                        onSubmitProof: p.isPending
                            ? () => _showPaymentProofDialog(p.id)
                            : null,
                        onViewProofs: p.hasProof
                            ? () => _showPaymentProofDialog(p.id)
                            : null,
                        onDetails: p.isPending
                            ? () => _openInstructions(p.id)
                            : null,
                      );
                    },
                  ),
                ),
                if (_historyTotalPages > 1)
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border:
                          Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: _historyPage > 1
                              ? () {
                                  setState(() => _historyPage--);
                                  _loadData();
                                }
                              : null,
                        ),
                        Text('$_historyPage / $_historyTotalPages',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontFamily: AppFonts.mono)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: _historyPage < _historyTotalPages
                              ? () {
                                  setState(() => _historyPage++);
                                  _loadData();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL SHARED BITS
// ─────────────────────────────────────────────────────────────────────────────

class _BalanceTag extends StatelessWidget {
  final String text;
  const _BalanceTag({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.cobalt50,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.cobalt200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: AppColors.cobalt),
            const SizedBox(width: 8),
            Text('$text left',
                style: TextStyle(
                    color: AppColors.cobalt,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      );
}

class _HeadCell {
  final String text;
  final int flex;
  final bool right;
  const _HeadCell(this.text, {this.flex = 1, this.right = false});
}

class _TableHead extends StatelessWidget {
  final List<_HeadCell> cells;
  const _TableHead({required this.cells});

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        color: AppColors.bgSubtle,
        child: Row(
          children: [
            for (final c in cells)
              Expanded(
                flex: c.flex,
                child: Align(
                  alignment:
                      c.right ? Alignment.centerRight : Alignment.centerLeft,
                  child: Text(
                    c.text,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CHECKOUT DIALOG
// Opened by Buy: confirms the pack and asks which crypto network to pay with.
// Pops with the chosen currency id, or null if cancelled.
// ─────────────────────────────────────────────────────────────────────────────

class _CheckoutDialog extends StatefulWidget {
  final CreditPack pack;
  final List<Map<String, String>> currencies;
  final String initial;

  const _CheckoutDialog({
    required this.pack,
    required this.currencies,
    required this.initial,
  });

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currencies.any((c) => c['id'] == widget.initial)
        ? widget.initial
        : widget.currencies.first['id']!;
  }

  /// Short network hint shown under each option, when we recognise it.
  static String? _networkHint(String id) {
    final v = id.toLowerCase();
    if (v.contains('trc20')) return 'Tron network · lowest fees';
    if (v.contains('erc20')) return 'Ethereum network · higher fees';
    if (v.contains('bep20') || v.contains('bsc')) return 'BNB Smart Chain';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final time = pack.streamingMinutes > 0
        ? '${pack.streamingMinutes} min streaming'
        : CreditDisplay.toTime(pack.credits.toDouble());

    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Checkout',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3)),
              const SizedBox(height: 16),

              // ── Order summary ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pack.label,
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('$time · ${pack.credits} credits',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Text('\$${pack.priceUsd}',
                        style: TextStyle(
                            fontFamily: AppFonts.display,
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Network choice ──────────────────────────────────────────
              Text('Pay with',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Send the exact amount on this network, or the payment '
                  'can be lost.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
              for (final c in widget.currencies) ...[
                _NetworkOption(
                  label: c['label']!,
                  hint: _networkHint(c['id']!),
                  selected: _selected == c['id'],
                  onTap: () => setState(() => _selected = c['id']!),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: Text('Continue · \$${pack.priceUsd}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkOption extends StatelessWidget {
  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  const _NetworkOption({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.cobalt50 : AppColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppColors.cobalt : AppColors.borderLight,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.currency_bitcoin_rounded,
                  size: 18,
                  color: selected ? AppColors.cobalt : AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (hint != null)
                      Text(hint!,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? AppColors.cobalt : AppColors.borderLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PACK ROW
// ─────────────────────────────────────────────────────────────────────────────

class _PackRow extends StatelessWidget {
  final CreditPack pack;
  final VoidCallback? onBuy; // null while a payment is being created
  final bool compact; // phone layout: two lines + button, no columns

  const _PackRow({required this.pack, required this.onBuy, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final timeStr = pack.streamingMinutes > 0
        ? '${pack.streamingMinutes}m 00s'
        : CreditDisplay.toTime(pack.credits.toDouble());

    if (compact) return _buildCompact(timeStr);

    return Container(
      constraints: const BoxConstraints(minHeight: 67),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      color: pack.popular ? AppColors.cobalt50.withValues(alpha: 0.6) : null,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(pack.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (pack.popular) ...[
                      const SizedBox(width: 8),
                      const ProTag('Popular'),
                    ],
                  ],
                ),
                if (pack.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(pack.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(timeStr,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${pack.credits}',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 38,
                child: pack.popular
                    ? ElevatedButton(
                        onPressed: onBuy,
                        style: ButtonStyle(
                          minimumSize:
                              WidgetStateProperty.all(const Size(96, 38)),
                          padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(horizontal: 16)),
                        ),
                        child: Text('Buy \$${pack.priceUsd}'),
                      )
                    : OutlinedButton(
                        onPressed: onBuy,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(96, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: Text('Buy \$${pack.priceUsd}'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(String timeStr) {
    const buttonPadding = EdgeInsets.symmetric(horizontal: 14);
    const buttonSize = Size(0, 38);
    return Container(
      constraints: const BoxConstraints(minHeight: 67),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: pack.popular ? AppColors.cobalt50.withValues(alpha: 0.6) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(pack.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (pack.popular) ...[
                      const SizedBox(width: 8),
                      const ProTag('Popular'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text('$timeStr  ·  ${pack.credits} credits',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          const SizedBox(width: 12),
          pack.popular
              ? ElevatedButton(
                  onPressed: onBuy,
                  style: ElevatedButton.styleFrom(
                      minimumSize: buttonSize, padding: buttonPadding),
                  child: Text('Buy \$${pack.priceUsd}'),
                )
              : OutlinedButton(
                  onPressed: onBuy,
                  style: OutlinedButton.styleFrom(
                      minimumSize: buttonSize, padding: buttonPadding),
                  child: Text('Buy \$${pack.priceUsd}'),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT HISTORY ROW
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentRow extends StatelessWidget {
  final Payment payment;
  final VoidCallback? onSubmitProof;
  final VoidCallback? onViewProofs;
  final VoidCallback? onDetails;
  const _PaymentRow({
    required this.payment,
    this.onSubmitProof,
    this.onViewProofs,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final date = payment.createdAt.length >= 10
        ? payment.createdAt.substring(0, 10)
        : payment.createdAt;
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.packLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${payment.currency.toUpperCase()} · $date · ${payment.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('\$${payment.amountUsd}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '+${CreditDisplay.toTime(payment.creditsToAdd.toDouble())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AppColors.success,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (payment.hasProof || payment.isPending) ...[
                      _ProofChip(payment: payment, onTap: onViewProofs),
                      const SizedBox(width: 8),
                    ],
                    if (onDetails != null) ...[
                      ProToolButton(
                        icon: Icons.account_balance_wallet_outlined,
                        tooltip: 'Payment details & wallet address',
                        onPressed: onDetails,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (payment.isPending && onSubmitProof != null) ...[
                      ProToolButton(
                        icon: Icons.upload_rounded,
                        tooltip: payment.hasProof
                            ? 'Re-upload proof of payment'
                            : 'Upload proof of payment',
                        onPressed: onSubmitProof,
                      ),
                      const SizedBox(width: 8),
                    ],
                    StatusBadge(status: payment.status),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill that tells the user whether proof was sent and received.
class _ProofChip extends StatelessWidget {
  final Payment payment;
  final VoidCallback? onTap;
  const _ProofChip({required this.payment, this.onTap});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String text;
    final String tip;
    final Color color;

    if (payment.proofReceived) {
      icon = Icons.verified_rounded;
      color = AppColors.success;
      text = payment.proofCount > 1
          ? 'Proof sent ×${payment.proofCount}'
          : 'Proof sent';
      tip = 'Last sent ${_fmtDateTime(payment.lastProofAt)} — click to view';
    } else if (payment.proofNeedsRetry) {
      icon = Icons.error_outline_rounded;
      color = AppColors.danger;
      text = 'Upload failed';
      tip = 'Your last upload didn\'t reach us. Please re-upload.';
    } else {
      icon = Icons.hourglass_empty_rounded;
      color = AppColors.textMuted;
      text = 'No proof';
      tip = 'No proof of payment sent yet';
    }

    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(text,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Info row for the pending instructions dialog
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Copy-to-clipboard button used in wallet address display
// ─────────────────────────────────────────────────────────────────────────────

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _copied
            ? Icon(Icons.check_rounded,
                key: ValueKey('check'), color: AppColors.success, size: 18)
            : Icon(Icons.copy_rounded,
                key: ValueKey('copy'),
                color: AppColors.textSecondary,
                size: 18),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT PROOF DIALOG
// Shows what was already sent for this payment (with thumbnails), then lets
// the user pick an image + optional tx hash / notes and upload (again).
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentProofDialog extends StatefulWidget {
  final String paymentId;
  final VoidCallback? onSubmitted;
  const _PaymentProofDialog({required this.paymentId, this.onSubmitted});

  @override
  State<_PaymentProofDialog> createState() => _PaymentProofDialogState();
}

class _PaymentProofDialogState extends State<_PaymentProofDialog> {
  final _txHashController = TextEditingController();
  final _notesController = TextEditingController();

  File? _pickedFile;
  bool _submitting = false;
  String? _errorMsg;
  bool _submitted = false;

  bool _loadingPrevious = true;
  List<PaymentProofInfo> _previous = [];
  bool _canUpload = true;
  String _paymentStatus = '';

  @override
  void initState() {
    super.initState();
    _loadPrevious();
  }

  @override
  void dispose() {
    _txHashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── What has already been sent for this payment ───────────────────────────
  Future<void> _loadPrevious() async {
    try {
      final res = await ApiService.instance.getPaymentProofs(widget.paymentId);
      if (!mounted) return;
      if ((res['statusCode'] as int? ?? 0) == 200) {
        setState(() {
          _previous = (res['results'] as List? ?? [])
              .map((j) => PaymentProofInfo.fromJson(j as Map<String, dynamic>))
              .toList();
          _canUpload = res['can_upload'] != false;
          _paymentStatus = res['status']?.toString() ?? '';
        });
      }
    } catch (_) {
      // Not fatal — the user can still upload.
    } finally {
      if (mounted) setState(() => _loadingPrevious = false);
    }
  }

  // ── Pick image ─────────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      final file = File(picked.path);
      final size = await file.length();
      if (size > _kMaxProofBytes) {
        setState(() {
          _pickedFile = null;
          _errorMsg = 'That image is larger than 10 MB. Please pick a smaller '
              'screenshot.';
        });
        return;
      }
      setState(() {
        _pickedFile = file;
        _errorMsg = null;
      });
    } catch (e) {
      setState(() => _errorMsg = 'Could not open the image picker: $e');
    }
  }

  void _choose() {
    // Desktop has no camera source in image_picker — go straight to files.
    if (_isDesktop) {
      _pickImage(ImageSource.gallery);
    } else {
      _showPickerSheet();
    }
  }

  // ── Submit to backend ──────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_pickedFile == null) {
      setState(
          () => _errorMsg = 'Please attach a screenshot or receipt first.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    Map<String, dynamic> result;
    try {
      result = await ApiService.instance.submitPaymentProof(
        paymentId: widget.paymentId,
        imageFile: _pickedFile!,
        txHash: _txHashController.text.trim(),
        notes: _notesController.text.trim(),
      );
    } catch (e) {
      result = {'statusCode': 0, 'error': ErrorHandler.sanitize(e)};
    }

    if (!mounted) return;

    final sc = result['statusCode'] as int? ?? 0;
    // 201 = stored on the server now; 200 = this exact upload was already
    // stored (retry after a dropped connection). Both mean "it's there".
    if (sc == 200 || sc == 201) {
      setState(() {
        _submitted = true;
        _submitting = false;
      });
      widget.onSubmitted?.call();
    } else {
      setState(() {
        _submitting = false;
        _errorMsg = result['error']?.toString() ??
            result['detail']?.toString() ??
            'Upload failed. Please try again.';
      });
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _submitted ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  // ── Success state ──────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded,
            color: AppColors.success, size: 52),
        const SizedBox(height: 14),
        Text(
          'Proof Received!',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Your screenshot is saved on our server. Our team will review your '
          'payment and add your credits shortly — you\'ll get an email once '
          'it\'s approved.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  // ── Previously submitted proofs ────────────────────────────────────────────
  Widget _previousSection() {
    if (_loadingPrevious) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(
          minHeight: 2,
          color: AppColors.accent,
          backgroundColor: AppColors.border,
        ),
      );
    }
    if (_previous.isEmpty) return const SizedBox.shrink();

    final latestMissing = !_previous.first.hasImage;
    final shown = _previous.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Already submitted (${_previous.length})',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSubtle,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.border),
                _PreviousProofTile(proof: shown[i]),
              ],
            ],
          ),
        ),
        if (_previous.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+ ${_previous.length - shown.length} older',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (latestMissing ? AppColors.danger : AppColors.cobalt)
                .withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(
                latestMissing
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                size: 16,
                color: latestMissing ? AppColors.danger : AppColors.cobalt),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                !_canUpload
                    ? 'This payment is ${_paymentStatus.isEmpty ? 'closed' : _paymentStatus} — no more uploads needed.'
                    : latestMissing
                        ? 'Your last upload didn\'t reach our server. Please upload it again below.'
                        : 'We already have your proof. Only upload again if you want to send a clearer or different screenshot — earlier ones stay attached.',
                style: TextStyle(
                    color: latestMissing ? AppColors.danger : AppColors.cobalt,
                    fontSize: 12,
                    height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  // ── Form state ─────────────────────────────────────────────────────────────
  Widget _buildForm() {
    final hasPrevious = _previous.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(children: [
          Icon(Icons.upload_file_rounded,
              color: AppColors.accent, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hasPrevious ? 'Payment Proof' : 'Submit Payment Proof',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                Text('Payment ${widget.paymentId}',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            icon: Icon(Icons.close_rounded,
                color: AppColors.textMuted, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
        const SizedBox(height: 16),

        _previousSection(),

        if (_canUpload) ..._uploadFields(hasPrevious),
      ],
    );
  }

  List<Widget> _uploadFields(bool hasPrevious) {
    return [
      Text(
        hasPrevious
            ? 'Upload another screenshot'
            : 'Upload a screenshot or photo of your transaction receipt.',
        style: TextStyle(
            color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
      ),
      Text('JPG, PNG or WEBP · max 10 MB',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
      const SizedBox(height: 12),

      // ── Image picker area ────────────────────────────────────────────────
      GestureDetector(
        onTap: _submitting ? null : _choose,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: _pickedFile == null ? 120 : 190,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _errorMsg != null && _pickedFile == null
                  ? AppColors.danger
                  : AppColors.accent.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: _pickedFile == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_rounded,
                        color: AppColors.accent, size: 34),
                    const SizedBox(height: 8),
                    Text(
                        _isDesktop
                            ? 'Click to choose a screenshot / receipt'
                            : 'Tap to attach screenshot / receipt',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    if (!_isDesktop) ...[
                      const SizedBox(height: 4),
                      Text('Gallery  ·  Camera',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(_pickedFile!, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _submitting
                            ? null
                            : () => setState(() => _pickedFile = null),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _submitting ? null : _choose,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Change',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 11)),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),

      if (_errorMsg != null && _pickedFile == null) ...[
        const SizedBox(height: 6),
        Text(_errorMsg!,
            style: TextStyle(color: AppColors.danger, fontSize: 12)),
      ],

      const SizedBox(height: 16),

      // ── Transaction hash (optional) ──────────────────────────────────────
      AppTextField(
        controller: _txHashController,
        label: 'Transaction hash or ID (optional)',
        hint: 'e.g. 0xabc123…',
        prefixIcon: Icons.tag_rounded,
        style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13.5,
            fontFamily: AppFonts.mono),
      ),

      const SizedBox(height: 16),

      // ── Notes (optional) ─────────────────────────────────────────────────
      AppTextField(
        controller: _notesController,
        label: 'Notes (optional)',
        hint: 'Anything that helps us verify the payment faster',
        maxLines: 3,
      ),

      // ── Generic error ────────────────────────────────────────────────────
      if (_errorMsg != null && _pickedFile != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 15),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_errorMsg!,
                    style: TextStyle(
                        color: AppColors.danger, fontSize: 12))),
          ]),
        ),
      ],

      const SizedBox(height: 20),

      // ── Submit button ────────────────────────────────────────────────────
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.upload_rounded, size: 16),
          label: Text(_submitting
              ? 'Uploading…'
              : (hasPrevious ? 'Upload Again' : 'Submit Proof')),
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    ];
  }

  // ── Bottom sheet for gallery / camera choice (mobile only) ─────────────────
  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.goldGlow,
                child: Icon(Icons.photo_library_rounded, color: AppColors.gold),
              ),
              title: Text('Choose from Gallery',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500)),
              subtitle: Text('Pick a saved screenshot',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.goldGlow,
                child: Icon(Icons.camera_alt_rounded, color: AppColors.gold),
              ),
              title: Text('Take a Photo',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500)),
              subtitle: Text('Photograph your receipt',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// One row in "Already submitted": thumbnail · when · tx hash · received?
class _PreviousProofTile extends StatelessWidget {
  final PaymentProofInfo proof;
  const _PreviousProofTile({required this.proof});

  void _openFull(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.bgCard,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                headers: ApiService.instance.imageHeaders,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text('Could not load image',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = proof.hasImage && proof.imagePath != null
        ? ApiService.instance.proofImageUrl(proof.imagePath!)
        : null;

    Widget thumb;
    if (url != null) {
      thumb = Image.network(
        url,
        headers: ApiService.instance.imageHeaders,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.image_outlined, color: AppColors.textMuted, size: 22),
      );
    } else {
      thumb = Icon(Icons.broken_image_outlined,
          color: AppColors.danger, size: 22);
    }

    return InkWell(
      onTap: url != null ? () => _openFull(context, url) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 44,
                height: 44,
                color: AppColors.bgElevated,
                alignment: Alignment.center,
                child: thumb,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sent ${_fmtDateTime(proof.submittedAt)}',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  if (proof.txHash.isNotEmpty)
                    Text(proof.txHash,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11.5,
                            fontFamily: AppFonts.mono)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              proof.hasImage ? 'Received' : 'Not received',
              style: TextStyle(
                  color: proof.hasImage ? AppColors.success : AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}