// lib/screens/account_suspended_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_gate.dart';
import '../services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';

/// Shown while the server reports the account as suspended. The user can
/// contact support, check again (e.g. after support lifts it) or sign out.
/// If they stay signed in, the background poll brings them back into the app
/// automatically once the suspension is lifted or expires.
class AccountSuspendedScreen extends StatefulWidget {
  const AccountSuspendedScreen({super.key});

  @override
  State<AccountSuspendedScreen> createState() => _AccountSuspendedScreenState();
}

class _AccountSuspendedScreenState extends State<AccountSuspendedScreen> {
  bool _checking = false;
  String? _note;
  Timer? _autoCheck;

  @override
  void initState() {
    super.initState();
    // Quietly re-check once a minute so a lifted or expired suspension lets
    // the user straight back in.
    _autoCheck = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _checking) return;
      final auth = context.read<AuthProvider>();
      if (auth.hasSession) auth.recheckAccountAccess();
    });
  }

  @override
  void dispose() {
    _autoCheck?.cancel();
    super.dispose();
  }

  Future<void> _checkAgain() async {
    setState(() {
      _checking = true;
      _note = null;
    });
    final ok = await context.read<AuthProvider>().recheckAccountAccess();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!ok) _note = 'Your account is still suspended.';
    });
  }

  Future<void> _contactSupport(String email) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': '${Brand.name} account suspended'},
    );
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<AppGate>();
    final status = gate.suspension;
    if (status == null) return Scaffold(backgroundColor: AppColors.bg);

    final signedIn = context.watch<AuthProvider>().hasSession;

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
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.tallyWash,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(Icons.block_rounded,
                        color: AppColors.tally, size: 30),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Account suspended',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    status.expiresAt != null
                        ? 'You can’t use ${Brand.name} until '
                            '${DateFormat('MMM d, h:mm a').format(status.expiresAt!)}.'
                        : 'You can’t use ${Brand.name} while your account is suspended.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                  if (status.reason.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
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
                          Text(
                            'REASON',
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              color: AppColors.textMuted,
                              fontSize: 11,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            status.reason,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'If you think this is a mistake, contact ${status.supportEmail}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (_note != null) ...[
                    Text(_note!,
                        style: TextStyle(
                            color: AppColors.tally, fontSize: 12.5)),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _contactSupport(status.supportEmail),
                      icon: const Icon(Icons.mail_outline_rounded, size: 18),
                      label: const Text('Contact support'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (signedIn) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _checking ? null : _checkAgain,
                            child: _checking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Check again'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              context.read<AuthProvider>().signOutFromGate(),
                          child: Text(signedIn ? 'Sign out' : 'Back to sign in'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
