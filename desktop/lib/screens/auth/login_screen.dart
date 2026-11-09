import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/brand.dart';
import '../../widgets/legal_dialog.dart';
import '../../widgets/viewfinder_frame.dart';

/// Sign in and create account, on one screen.
///
/// Wide windows: the dark brand monitor on the left, the form on the right.
/// Narrow windows: the form only, with the logo above it.
class LoginScreen extends StatefulWidget {
  /// Opens on the "Create account" tab (used by the welcome tour).
  final bool startInRegister;
  const LoginScreen({super.key, this.startInRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late bool _isRegister = widget.startInRegister;
  bool _agreedToTerms = false;
  bool _termsError = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isRegister && !_agreedToTerms) {
      setState(() => _termsError = true);
      return;
    }

    final auth = context.read<AuthProvider>();

    bool success;
    if (_isRegister) {
      success = await auth.register(
        _emailCtrl.text.trim(),
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );
    } else {
      success = await auth.login(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
    }

    if (success && mounted) {
      context.go('/dashboard');
    }
  }

  void _setMode(bool register) {
    if (register == _isRegister) return;
    context.read<AuthProvider>().clearError();
    _formKey.currentState?.reset();
    setState(() {
      _isRegister = register;
      _agreedToTerms = false;
      _termsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 940;

    return Scaffold(
      backgroundColor: AppColors.bgCard,
      body: Row(
        children: [
          if (wide)
            const Expanded(
              flex: 5,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: _BrandPanel(),
              ),
            ),
          Expanded(
            flex: 4,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!wide) ...[
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: BrandLockup(height: 30),
                              ),
                              const SizedBox(height: 40),
                            ],
                            Text(
                              _isRegister
                                  ? 'Create your account'
                                  : 'Welcome back',
                              style: Theme.of(context).textTheme.displayMedium,
                            ).animate().fadeIn(duration: 300.ms),
                            const SizedBox(height: 8),
                            Text(
                              _isRegister
                                  ? 'Start streaming in minutes. Pay only for the time you use.'
                                  : 'Sign in to continue to your studio.',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15,
                                  height: 1.5),
                            ).animate().fadeIn(delay: 60.ms),
                            const SizedBox(height: 28),
                            _ModeSwitch(
                              register: _isRegister,
                              onChanged: _setMode,
                            ),
                            const SizedBox(height: 24),
                            if (auth.error != null) ...[
                              _ErrorNote(auth.error!).animate().shake(hz: 3),
                              const SizedBox(height: 18),
                            ],
                            AppTextField(
                              controller: _emailCtrl,
                              label: 'Email',
                              hint: 'you@example.com',
                              prefixIcon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Enter your email address';
                                }
                                if (!v.contains('@') || !v.contains('.')) {
                                  return 'That email address doesn’t look right';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            if (_isRegister) ...[
                              AppTextField(
                                controller: _usernameCtrl,
                                label: 'Username',
                                hint: 'How we should greet you',
                                prefixIcon: Icons.person_outline_rounded,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                validator: (v) {
                                  if (_isRegister &&
                                      (v == null || v.trim().isEmpty)) {
                                    return 'Choose a username';
                                  }
                                  return null;
                                },
                              ).animate().fadeIn(duration: 220.ms),
                              const SizedBox(height: 18),
                            ],
                            AppTextField(
                              controller: _passwordCtrl,
                              label: 'Password',
                              hint: _isRegister
                                  ? 'At least 8 characters'
                                  : 'Your password',
                              prefixIcon: Icons.lock_outline_rounded,
                              isPassword: true,
                              textInputAction: TextInputAction.done,
                              autofillHints: [
                                _isRegister
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password
                              ],
                              labelTrailing: _isRegister
                                  ? null
                                  : InlineLink('Forgot password?',
                                      onTap: () =>
                                          context.push('/forgot-password')),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Enter your password';
                                }
                                if (_isRegister && v.length < 8) {
                                  return 'Use at least 8 characters';
                                }
                                return null;
                              },
                              onSubmitted: (_) => _submit(),
                            ),
                            if (_isRegister) ...[
                              const SizedBox(height: 20),
                              _TermsCheckbox(
                                value: _agreedToTerms,
                                hasError: _termsError,
                                onChanged: (v) => setState(() {
                                  _agreedToTerms = v ?? false;
                                  if (_agreedToTerms) _termsError = false;
                                }),
                                onTermsTap: () =>
                                    LegalDialog.showTerms(context),
                                onPrivacyTap: () =>
                                    LegalDialog.showPrivacy(context),
                              ),
                            ],
                            const SizedBox(height: 26),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: auth.isLoading ? null : _submit,
                                child: auth.isLoading
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2),
                                      )
                                    : Text(
                                        _isRegister
                                            ? 'Create account'
                                            : 'Sign in',
                                        style: const TextStyle(fontSize: 15),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _isRegister
                                      ? 'Already have an account?'
                                      : 'New to ${Brand.name}?',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14),
                                ),
                                TextButton(
                                  onPressed: () => _setMode(!_isRegister),
                                  child: Text(_isRegister
                                      ? 'Sign in'
                                      : 'Create an account'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sign in / Create account segmented switch.
class _ModeSwitch extends StatelessWidget {
  final bool register;
  final ValueChanged<bool> onChanged;
  const _ModeSwitch({required this.register, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool value) {
      final on = register == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? AppColors.bgCard : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm - 2),
                  boxShadow: on ? AppShadows.sm : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color:
                        on ? AppColors.textPrimary : AppColors.textSecondary,
                    fontSize: 13.5,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bgHover,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child:
          Row(children: [seg('Sign in', false), seg('Create account', true)]),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String text;
  const _ErrorNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tallyWash,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.tally.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.tally),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: AppColors.dangerText, fontSize: 13.5, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  final bool value;
  final bool hasError;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onTermsTap;
  final VoidCallback onPrivacyTap;

  const _TermsCheckbox({
    required this.value,
    required this.hasError,
    required this.onChanged,
    required this.onTermsTap,
    required this.onPrivacyTap,
  });

  @override
  Widget build(BuildContext context) {
    final link = TextStyle(
      color: AppColors.cobalt,
      fontWeight: FontWeight.w600,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: hasError
                    ? BorderSide(color: AppColors.tally, width: 1.5)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms of Use',
                      style: link,
                      recognizer: TapGestureRecognizer()..onTap = onTermsTap,
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: link,
                      recognizer: TapGestureRecognizer()..onTap = onPrivacyTap,
                    ),
                    const TextSpan(
                        text:
                            ', and I will only use faces I have permission to use.'),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (hasError) ...[
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 32),
            child: Text(
              'Please agree to continue',
              style: TextStyle(color: AppColors.tally, fontSize: 12.5),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Brand panel ───────────────────────────────────────────────────────────────
//
// The dark monitor: logo, one strong line, what you get, and a running
// timecode. The product, not a marketing gradient.

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _points = [
    (
      Icons.bolt_rounded,
      'Real time',
      'Your face is mapped as you move, with no render step.'
    ),
    (
      Icons.cast_rounded,
      'Works with your tools',
      'Send the output to OBS, Zoom, Meet or any call.'
    ),
    (
      Icons.timer_outlined,
      'Pay per second',
      'Top up with crypto and only pay for the time you stream.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg + 4),
      child: Container(
        color: AppColors.screen,
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.7, -0.6),
                    radius: 1.1,
                    colors: [Color(0x553A3DFF), Color(0x000F1117)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 40, 48, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandLockup(height: 32, onDark: true),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.screenRaised,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.screenBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LiveDot(size: 7),
                        SizedBox(width: 8),
                        Text('Live face streaming for creators',
                            style: TextStyle(
                                color: AppColors.screenText,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ).animate().fadeIn(duration: 300.ms),
                  const SizedBox(height: 20),
                  const Text(
                    'Change what the camera sees, while it’s still rolling.',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      color: AppColors.screenText,
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.4,
                      height: 1.08,
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                  const SizedBox(height: 36),
                  for (var i = 0; i < _points.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.screenRaised,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                              border:
                                  Border.all(color: AppColors.screenBorder),
                            ),
                            child: Icon(_points[i].$1,
                                size: 18, color: AppColors.cobaltLight),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_points[i].$2,
                                    style: const TextStyle(
                                        color: AppColors.screenText,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(_points[i].$3,
                                    style: const TextStyle(
                                        color: AppColors.screenMuted,
                                        fontSize: 14,
                                        height: 1.45)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(delay: (180 + 80 * i).ms, duration: 350.ms),
                  const Spacer(),
                  const Row(
                    children: [
                      Text(
                        Brand.domain,
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          color: AppColors.screenMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      Spacer(),
                      _TickingTimecode(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TickingTimecode extends StatefulWidget {
  const _TickingTimecode();

  @override
  State<_TickingTimecode> createState() => _TickingTimecodeState();
}

class _TickingTimecodeState extends State<_TickingTimecode> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = null;
    if (!MediaQuery.of(context).disableAnimations) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = Duration(seconds: _seconds);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LiveDot(size: 7),
          const SizedBox(width: 8),
          Text(
            '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              color: AppColors.screenMuted,
              fontSize: 12.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
