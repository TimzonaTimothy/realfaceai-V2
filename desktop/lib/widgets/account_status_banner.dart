import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/account_status.dart';
import '../services/auth_provider.dart';
import '../theme/app_theme.dart';

/// Strip across the top of every page while the account is frozen, so the
/// user knows why streaming / buying credits won't work before they try.
class AccountStatusBanner extends StatelessWidget {
  const AccountStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context
        .select<AuthProvider, AccountStatus?>((a) => a.user?.accountStatus);
    if (status == null || !status.isFrozen) return const SizedBox.shrink();

    final until = status.expiresAt != null
        ? ' until ${DateFormat('MMM d, h:mm a').format(status.expiresAt!)}'
        : '';
    final reason = status.reason.isNotEmpty ? ' Reason: ${status.reason}.' : '';

    return Material(
      color: AppColors.warningWash,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x33B86E00))),
        ),
        child: Row(
          children: [
            Icon(Icons.ac_unit_rounded, size: 16, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your account is frozen$until. You can view your account, but '
                'streaming, generation and payments are paused.$reason '
                'Contact ${status.supportEmail} for help.',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
