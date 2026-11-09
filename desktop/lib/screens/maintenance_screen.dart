// lib/screens/maintenance_screen.dart
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/maintenance_info.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import '../utils/maintenance_exception.dart';

class MaintenanceScreen extends StatefulWidget {
  final MaintenanceInfo info;

  const MaintenanceScreen({super.key, required this.info});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  Timer? _countdownTimer;
  int _secondsLeft = 0;
  bool _checking = false;
  String? _errorMsg;

  // Live countdown to scheduled end (separate from retry countdown)
  Duration? _untilEnd;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.info.retryAfter.clamp(10, 3600);
    _untilEnd = widget.info.timeUntilEnd;
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        // Retry countdown
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          _countdownTimer?.cancel();
          _checkIfBack();
        }

        // Scheduled-end live countdown
        _untilEnd = widget.info.timeUntilEnd;
      });
    });
  }

  // ── Check if server is back ────────────────────────────────────────────────

  Future<void> _checkIfBack() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _errorMsg = null;
    });

    try {
      await ApiService.instance.healthCheck();
      if (!mounted) return;
      // Clear maintenance state FIRST — then let the router redirect naturally
      await context.read<AuthProvider>().clearMaintenance();
      // No context.go() needed — clearMaintenance() calls notifyListeners()
      // which triggers the GoRouter redirect automatically
    } on MaintenanceException catch (e) {
      if (!mounted) return;
      setState(() {
        _secondsLeft = e.info.retryAfter.clamp(10, 3600);
        _checking = false;
      });
      _startCountdown();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'Could not reach server. Retrying automatically…';
        _secondsLeft = 60;
        _checking = false;
      });
      _startCountdown();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatCountdown(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatDuration(Duration d) {
    if (d.inHours >= 1) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return '$h h ${m.toString().padLeft(2, '0')} min';
    }
    if (d.inMinutes >= 1) {
      final m = d.inMinutes;
      final s = d.inSeconds.remainder(60);
      return '$m min ${s.toString().padLeft(2, '0')} s';
    }
    return '${d.inSeconds} s';
  }

  String _formatDateTime(DateTime dt) => DateFormat('MMM d, h:mm a').format(dt);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
             constraints: const BoxConstraints(maxWidth: 460),
             child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLockup(height: 30),
                const SizedBox(height: 36),
                _buildIcon(),
                const SizedBox(height: 28),
                _buildTitle(),
                const SizedBox(height: 12),
                _buildMessage(),
                const SizedBox(height: 28),

                // ── Scheduled window (if provided by backend) ────────────
                if (widget.info.hasSchedule) ...[
                  _buildScheduleCard(),
                  const SizedBox(height: 20),
                ],

                // ── Auto-retry countdown ─────────────────────────────────
                _buildRetryCountdown(),
                const SizedBox(height: 20),

                // ── Error hint ───────────────────────────────────────────
                if (_errorMsg != null) ...[
                  _buildErrorHint(),
                  const SizedBox(height: 16),
                ],

                // ── Manual check button ──────────────────────────────────
                _buildCheckButton(),
              ],
             ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.cobalt50,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Icon(
        Icons.construction_rounded,
        color: AppColors.cobalt,
        size: 30,
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      widget.info.title ?? 'We’ll be right back',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.displaySmall,
    );
  }

  Widget _buildMessage() {
    return Text(
      widget.info.message,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 15,
        height: 1.6,
      ),
    );
  }

  // Shows the scheduled start/end window + live remaining time
  Widget _buildScheduleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 17, color: AppColors.cobalt),
              SizedBox(width: 8),
              Text(
                'Scheduled window',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Start time
          if (widget.info.scheduledStart != null)
            _scheduleRow(
              'Starts',
              _formatDateTime(widget.info.scheduledStart!),
            ),

          // End time
          if (widget.info.scheduledEnd != null) ...[
            const SizedBox(height: 6),
            _scheduleRow(
              'Expected end',
              _formatDateTime(widget.info.scheduledEnd!),
            ),
          ],

          // Live time remaining
          if (_untilEnd != null && _untilEnd! > Duration.zero) ...[
            const SizedBox(height: 10),
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Est. time remaining  ',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(_untilEnd!),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _scheduleRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRetryCountdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.xs,
      ),
      child: Column(
        children: [
          Text(
            _checking ? 'Checking the server…' : 'Checking again in',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _checking
              ? SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    color: AppColors.accent,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  _formatCountdown(_secondsLeft),
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    color: AppColors.textPrimary,
                    fontSize: 40,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildErrorHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x14E5322D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x55E5322D)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.tally),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMsg!,
              style: TextStyle(
                color: AppColors.tally,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _checking ? null : _checkIfBack,
        child: _checking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Check now'),
      ),
    );
  }
}
