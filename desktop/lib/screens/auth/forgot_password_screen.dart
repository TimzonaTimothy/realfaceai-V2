import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/brand.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  // 0 = email, 1 = OTP + new password, 2 = success
  int _step = 0;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Step 1: Request OTP ───────────────────────────────────────────────────

  Future<void> _sendOTP() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.instance.desktopForgotPassword(
        _emailCtrl.text.trim().toLowerCase(),
      );
      if (!mounted) return;

      if (result['ok'] == true) {
        setState(() {
          _step = 1;
        });
      } else {
        setState(() {
          _error = result['error'] ?? 'Something went wrong.';
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Connection error. Check your internet.';
      });
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  // ── Step 2: Verify OTP + reset password ───────────────────────────────────

  Future<void> _verifyOTP() async {
    if (!_otpFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ApiService.instance.desktopVerifyOTP(
        email: _emailCtrl.text.trim().toLowerCase(),
        code: _codeCtrl.text.trim(),
        newPassword: _newPwCtrl.text,
        confirmPassword: _confirmCtrl.text,
      );
      if (!mounted) return;

      if (result['ok'] == true) {
        setState(() {
          _step = 2;
        });
      } else {
        setState(() {
          _error = result['error'] ?? 'Verification failed.';
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Connection error. Check your internet.';
      });
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 28,
              top: 24,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => context.go('/login'),
                child: const BrandLockup(height: 28),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 88, 20, 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Stepper(step: _step),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border),
                          boxShadow: AppShadows.sm,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: KeyedSubtree(
                            key: ValueKey(_step),
                            child: _step == 0
                                ? _buildEmailStep()
                                : _step == 1
                                    ? _buildOTPStep()
                                    : _buildSuccessStep(),
                          ),
                        ),
                      ),
                      if (_step < 2) ...[
                        const SizedBox(height: 20),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => context.go('/login'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary),
                            icon: const Icon(Icons.arrow_back_rounded,
                                size: 16),
                            label: const Text('Back to sign in'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(IconData icon, String title, String body,
      {Color? tint}) {
    tint ??= AppColors.cobalt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: tint, size: 24),
        ),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(body,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14.5, height: 1.55)),
        const SizedBox(height: 26),
      ],
    );
  }

  // ── Step 0: Email ─────────────────────────────────────────────────────────

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(Icons.lock_reset_rounded, 'Reset your password',
              'Enter the email on your account and we’ll send you a 6-digit code.'),
          if (_error != null) _errorBanner(_error!),
          AppTextField(
            controller: _emailCtrl,
            label: 'Email',
            hint: 'you@example.com',
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Enter your email address';
              }
              if (!v.contains('@') || !v.contains('.')) {
                return 'That email address doesn’t look right';
              }
              return null;
            },
            onSubmitted: (_) => _sendOTP(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOTP,
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Send reset code'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: OTP + New Password ────────────────────────────────────────────

  Widget _buildOTPStep() {
    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(Icons.mark_email_read_outlined, 'Check your inbox',
              'We sent a 6-digit code to ${_emailCtrl.text.trim()}. Enter it below with your new password.'),
          if (_error != null) _errorBanner(_error!),
          AppTextField(
            controller: _codeCtrl,
            label: 'Reset code',
            hint: '000000',
            keyboardType: TextInputType.number,
            autofocus: true,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: TextStyle(
              fontFamily: AppFonts.mono,
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 10,
            ),
            labelTrailing: InlineLink('Resend code', onTap: () {
              if (_isLoading) return;
              setState(() => _error = null);
              _sendOTP();
            }),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Enter the code from the email';
              if (v.length != 6) return 'The code has 6 digits';
              return null;
            },
          ),
          const SizedBox(height: 18),
          AppTextField(
            controller: _newPwCtrl,
            label: 'New password',
            hint: 'At least 8 characters',
            prefixIcon: Icons.lock_outline_rounded,
            isPassword: true,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Choose a new password';
              if (v.length < 8) return 'Use at least 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 18),
          AppTextField(
            controller: _confirmCtrl,
            label: 'Confirm new password',
            hint: 'Type it again',
            prefixIcon: Icons.lock_outline_rounded,
            isPassword: true,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Confirm your new password';
              if (v != _newPwCtrl.text) return 'Passwords don’t match';
              return null;
            },
            onSubmitted: (_) => _verifyOTP(),
          ),
          const SizedBox(height: 26),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyOTP,
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Reset password'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() {
              _step = 0;
              _error = null;
              _codeCtrl.clear();
            }),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Use a different email'),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Success ───────────────────────────────────────────────────────

  Widget _buildSuccessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(Icons.check_rounded, 'Password updated',
            'Your password has been changed. Sign in with your new password to continue.',
            tint: AppColors.success),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () => context.go('/login'),
            child: const Text('Continue to sign in'),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 250.ms);
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: AppColors.tallyWash,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.tally.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: AppColors.tally, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: AppColors.dangerText, fontSize: 13.5),
            ),
          ),
        ],
      ),
    ).animate().shake(hz: 3);
  }
}

/// Email → Code → Done.
class _Stepper extends StatelessWidget {
  final int step;
  const _Stepper({required this.step});

  @override
  Widget build(BuildContext context) {
    const labels = ['Email', 'Code', 'Done'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: i <= step ? AppColors.cobalt : AppColors.border,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: i < step
                      ? AppColors.cobalt
                      : i == step
                          ? AppColors.cobalt50
                          : AppColors.bgCard,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: i <= step ? AppColors.cobalt : AppColors.borderLight),
                ),
                alignment: Alignment.center,
                child: i < step
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : Text('${i + 1}',
                        style: TextStyle(
                            color: i == step
                                ? AppColors.cobalt
                                : AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(labels[i],
                  style: TextStyle(
                      color: i <= step
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: i == step ? FontWeight.w600 : FontWeight.w500)),
            ],
          ),
        ],
      ],
    );
  }
}
