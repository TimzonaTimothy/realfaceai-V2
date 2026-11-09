import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pro_layout.dart';

/// Security — change password.
///
///   Toolbar
///   ┌ Password form (current / new | confirm, pinned actions) ┬ Requirements ┐
///   │                                                         ├ Account      ┤
///
/// Requirements tick off live as you type, so there is no separate "tips"
/// block to read. Under 820 px the right column stacks below the form.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _isLoading = false;
  bool _success = false;
  String? _error;

  // ── Live rules (drive both the checklist and the strength meter) ────────
  bool get _hasLength => _newCtrl.text.length >= 8;
  bool get _hasMixedCase =>
      RegExp(r'[A-Z]').hasMatch(_newCtrl.text) &&
      RegExp(r'[a-z]').hasMatch(_newCtrl.text);
  bool get _hasNumOrSymbol =>
      RegExp(r'[0-9]').hasMatch(_newCtrl.text) ||
      RegExp(r'[^A-Za-z0-9]').hasMatch(_newCtrl.text);
  bool get _differs =>
      _newCtrl.text.isNotEmpty && _newCtrl.text != _currentCtrl.text;
  bool get _matches =>
      _confirmCtrl.text.isNotEmpty && _confirmCtrl.text == _newCtrl.text;

  _PasswordStrength get _strength {
    final p = _newCtrl.text;
    if (p.length < 8) return _PasswordStrength.weak;
    int score = 0;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    if (score <= 1) return _PasswordStrength.fair;
    if (score <= 2) return _PasswordStrength.good;
    return _PasswordStrength.strong;
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.instance.desktopChangePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
        confirmPassword: _confirmCtrl.text,
      );
      if (!mounted) return;
      if (result['ok'] == true) {
        setState(() => _success = true);
      } else {
        setState(() => _error =
            result['error'] ?? 'Failed to change password. Try again.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Connection error. Check your internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const ProToolbar(
            icon: Icons.shield_rounded,
            title: 'Security',
            subtitle: 'Keep your account safe with a strong, unique password.',
          ),
          Expanded(child: _success ? _successState() : _workspace()),
        ],
      ),
    );
  }

  Widget _workspace() {
    return LayoutBuilder(builder: (context, c) {
      const gap = 16.0;
      final wide = c.maxWidth >= 820;
      final side = c.maxWidth < 760 ? 16.0 : 28.0;
      if (wide) {
        return Padding(
          padding: EdgeInsets.fromLTRB(side, 18, side, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _formPanel(twoCol: c.maxWidth >= 1000)),
              const SizedBox(width: gap),
              SizedBox(
                width: 340,
                child: Column(
                  children: [
                    Expanded(flex: 5, child: _requirementsPanel()),
                    const SizedBox(height: gap),
                    Expanded(flex: 4, child: _accountPanel()),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(side, 18, side, 24),
        child: Column(
          children: [
            SizedBox(height: 520, child: _formPanel(twoCol: false)),
            const SizedBox(height: gap),
            SizedBox(height: 300, child: _requirementsPanel()),
            const SizedBox(height: gap),
            SizedBox(height: 260, child: _accountPanel()),
          ],
        ),
      );
    });
  }

  // ── Form ────────────────────────────────────────────────────────────────
  Widget _formPanel({required bool twoCol}) {
    final current = _field(
      label: 'Current password',
      controller: _currentCtrl,
      hint: 'Enter your current password',
      icon: Icons.lock_outline,
      visible: _showCurrent,
      toggle: () => setState(() => _showCurrent = !_showCurrent),
      onChanged: (_) => setState(() {}),
      validator: (v) => (v == null || v.isEmpty)
          ? 'Current password is required'
          : null,
    );
    final next = _field(
      label: 'New password',
      controller: _newCtrl,
      hint: 'Enter new password',
      icon: Icons.lock_reset_rounded,
      visible: _showNew,
      toggle: () => setState(() => _showNew = !_showNew),
      onChanged: (_) => setState(() {}),
      validator: (v) {
        if (v == null || v.isEmpty) return 'New password is required';
        if (v.length < 8) return 'Must be at least 8 characters';
        if (v == _currentCtrl.text) return 'Must differ from current password';
        return null;
      },
    );
    final confirm = _field(
      label: 'Confirm new password',
      controller: _confirmCtrl,
      hint: 'Re-enter new password',
      icon: Icons.lock_outline,
      visible: _showConfirm,
      toggle: () => setState(() => _showConfirm = !_showConfirm),
      onChanged: (_) => setState(() {}),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Please confirm your new password';
        if (v != _newCtrl.text) return 'Passwords do not match';
        return null;
      },
    );

    return ProPanel(
      title: 'Change password',
      icon: Icons.lock_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.tallyWash,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                      color: AppColors.tally.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: AppColors.danger, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: AppColors.dangerText, fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: current,
            ),
            const SizedBox(height: 22),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 22),
            if (twoCol)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: next),
                  const SizedBox(width: 16),
                  Expanded(child: confirm),
                ],
              )
            else ...[
              next,
              const SizedBox(height: 18),
              confirm,
            ],
            const SizedBox(height: 26),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Update password'),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => context.go('/dashboard'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool visible,
    required VoidCallback toggle,
    required ValueChanged<String> onChanged,
    required String? Function(String?) validator,
  }) {
    return AppTextField(
      controller: controller,
      label: label,
      hint: hint,
      prefixIcon: icon,
      isPassword: true,
      onChanged: onChanged,
      validator: validator,
    );
  }

  // ── Requirements (live) ─────────────────────────────────────────────────
  Widget _requirementsPanel() {
    final s = _strength;
    final typed = _newCtrl.text.isNotEmpty;
    final level = typed ? _PasswordStrength.values.indexOf(s) + 1 : 0;
    return ProPanel(
      title: 'Requirements',
      icon: Icons.rule_rounded,
      trailing: typed ? ProTag(s.label, color: s.color) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 6,
                    decoration: BoxDecoration(
                      color: i < level ? s.color : AppColors.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _rule('At least 8 characters', _hasLength, typed),
          _rule('Upper and lower case letters', _hasMixedCase, typed),
          _rule('A number or special character', _hasNumOrSymbol, typed),
          _rule('Different from current password', _differs, typed),
          _rule('Confirmation matches', _matches, _confirmCtrl.text.isNotEmpty),
        ],
      ),
    );
  }

  Widget _rule(String text, bool ok, bool active) {
    final c = !active
        ? AppColors.textMuted
        : (ok ? AppColors.success : AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            ok && active
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            size: 18,
            color: ok && active ? AppColors.success : AppColors.borderLight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: ok && active ? AppColors.textPrimary : c,
                    fontSize: 14)),
          ),
        ],
      ),
    );
  }

  // ── Account ─────────────────────────────────────────────────────────────
  Widget _accountPanel() {
    final u = context.watch<AuthProvider>().user;
    String since = u?.createdAt ?? '–';
    if (since.length >= 10) since = since.substring(0, 10);
    return ProPanel(
      title: 'Account',
      icon: Icons.person_outline_rounded,
      child: Column(
        children: [
          ProKv('Email', u?.email ?? '–'),
          ProKv('Username', u?.username ?? '–'),
          ProKv('Plan', () {
            final p = (u?.plan ?? '–').toString();
            return p.isEmpty ? p : p[0].toUpperCase() + p.substring(1);
          }()),
          ProKv(
            'Email verified',
            (u?.isVerified ?? false) ? 'Yes' : 'No',
            valueColor:
                (u?.isVerified ?? false) ? AppColors.success : AppColors.warning,
          ),
          ProKv('Member since', since, mono: true, last: true),
        ],
      ),
    );
  }

  // ── Success ─────────────────────────────────────────────────────────────
  Widget _successState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: AppColors.successWash, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded,
                    color: AppColors.success, size: 30),
              ),
              const SizedBox(height: 16),
              Text('Password updated',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4)),
              const SizedBox(height: 8),
              Text(
                'Your password has been changed.\nA confirmation email is on its way.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/dashboard'),
                  child: const Text('Back to dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PasswordStrength {
  weak('Weak'),
  fair('Fair'),
  good('Good'),
  strong('Strong');

  final String label;
  const _PasswordStrength(this.label);

  Color get color => switch (this) {
        weak => AppColors.danger,
        fair => AppColors.warning,
        good => AppColors.info,
        strong => AppColors.success,
      };
}