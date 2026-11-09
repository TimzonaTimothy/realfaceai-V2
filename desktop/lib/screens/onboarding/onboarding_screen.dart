import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/viewfinder_frame.dart';

/// First-run welcome tour. Three short steps, shown once per device:
///
///   1. What RealFaceAI is
///   2. How a session works (face → studio → stream)
///   3. Responsible use, then create an account or sign in
///
/// Layout: copy and controls on a white panel, an illustration of the step
/// on the dark monitor surface. Under 900 px the monitor is hidden.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Step {
  final String eyebrow;
  final String title;
  final String body;
  const _Step(this.eyebrow, this.title, this.body);
}

const _steps = [
  _Step(
    'Welcome to RealFaceAI',
    'Be anyone on camera, live.',
    'RealFaceAI maps a face onto your video in real time, right on your '
        'desktop. No green screen and nothing to edit afterwards.',
  ),
  _Step(
    'How it works',
    'Three steps from photo to live stream.',
    'Pick a clear photo of a face, launch the studio, then send the output '
        'to OBS or your video call. You only pay for the seconds you stream.',
  ),
  _Step(
    'Before you start',
    'Use real faces responsibly.',
    'Only use faces you have permission to use, never to deceive or harm '
        'anyone, and only if you are 18 or older. These rules are part of '
        'our Terms and protect everyone on camera.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;

  bool get _last => _index == _steps.length - 1;

  void _next() {
    if (_last) {
      _finish(register: true);
    } else {
      setState(() => _index++);
    }
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _finish({required bool register}) async {
    final router = GoRouter.of(context);
    await context.read<AuthProvider>().completeOnboarding();
    router.go(register ? '/login?mode=register' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      body: Row(
        children: [
          Expanded(
            flex: 11,
            child: SafeArea(child: _content(context)),
          ),
          if (wide)
            Expanded(
              flex: 13,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _Stage(index: _index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final step = _steps[_index];
    return LayoutBuilder(builder: (context, c) {
      final hPad = c.maxWidth < 520 ? 24.0 : 56.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BrandLockup(height: 30),
                const Spacer(),
                if (!_last)
                  TextButton(
                    onPressed: () => _finish(register: false),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary),
                    child: const Text('Skip'),
                  ),
              ],
            ),
            const Spacer(flex: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.04), end: Offset.zero)
                        .animate(a),
                    child: child,
                  ),
                ),
                child: Column(
                  key: ValueKey(_index),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.cobalt50,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        step.eyebrow,
                        style: TextStyle(
                          color: AppColors.cobalt,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(step.title,
                        style: Theme.of(context).textTheme.displayLarge),
                    const SizedBox(height: 16),
                    Text(
                      step.body,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    if (_index == 2) ...[
                      const SizedBox(height: 22),
                      const _Promise(
                          icon: Icons.verified_user_outlined,
                          text: 'I have permission for every face I use'),
                      const _Promise(
                          icon: Icons.do_not_disturb_on_outlined,
                          text: 'I will not impersonate anyone to deceive'),
                      const _Promise(
                          icon: Icons.cake_outlined,
                          text: 'I am 18 or older'),
                    ],
                  ],
                ),
              ),
            ),
            const Spacer(flex: 4),
            _ProgressBar(count: _steps.length, index: _index),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Row(
                children: [
                  if (_index > 0)
                    OutlinedButton(
                      onPressed: _back,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(96, 48)),
                      child: const Text('Back'),
                    ),
                  if (_index > 0) const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _next,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_last ? 'Agree and create account' : 'Continue'),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Already have an account?',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
                TextButton(
                  onPressed: () => _finish(register: false),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _Promise extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Promise({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 17, color: AppColors.cobalt),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int count;
  final int index;
  const _ProgressBar({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: i == index ? 36 : 14,
            height: 6,
            decoration: BoxDecoration(
              color: i <= index ? AppColors.cobalt : AppColors.border,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(width: 6),
        ],
        const SizedBox(width: 8),
        Text('${index + 1} of $count',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ── The monitor stage: one illustration per step ──────────────────────────────

class _Stage extends StatelessWidget {
  final int index;
  const _Stage({required this.index});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg + 4),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.screen),
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.1),
                    radius: 0.85,
                    colors: [Color(0x553A3DFF), Color(0x000F1117)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.97, end: 1.0).animate(a),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(index),
                  child: switch (index) {
                    0 => const _LiveScene(),
                    1 => const _PipelineScene(),
                    _ => const _ConsentScene(),
                  },
                ),
              ),
            ),
            const Positioned(
              left: 28,
              bottom: 24,
              child: Text(
                Brand.domain,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  color: AppColors.screenMuted,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Step 1: the mark, live, inside a viewfinder.
class _LiveScene extends StatelessWidget {
  const _LiveScene();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 440,
        height: 360,
        child: ViewfinderFrame(
          bracketColor: AppColors.cobaltLight,
          arm: 34,
          stroke: 3,
          padding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              Center(
                child: SvgPicture.asset('assets/brand/face-white.svg',
                        width: 200, height: 180)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(
                        begin: 1, end: 1.03, duration: 1800.ms,
                        curve: Curves.easeInOut),
              ),
              const Positioned(
                left: 0,
                top: 0,
                child: _Chip(live: true, text: 'Live'),
              ),
              const Positioned(
                right: 0,
                bottom: 0,
                child: Text(
                  '00:00:37',
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    color: AppColors.screenMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final bool live;
  final String text;
  const _Chip({required this.live, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: live ? AppColors.tally : AppColors.screenRaised,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            const LiveDot(color: Colors.white, size: 6),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2: photo → studio → stream.
class _PipelineScene extends StatelessWidget {
  const _PipelineScene();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.add_photo_alternate_outlined, 'Choose a face', 'A clear, front-facing photo'),
      (Icons.center_focus_strong_rounded, 'Launch the studio', 'Your camera, mapped in real time'),
      (Icons.cast_rounded, 'Go live', 'Send to OBS, Zoom, Meet and more'),
    ];
    return Center(
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.screenRaised,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: i == 1 ? AppColors.cobaltLight : AppColors.screenBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: i == 1 ? AppColors.cobalt : AppColors.screen,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(items[i].$1,
                          size: 21,
                          color: i == 1 ? Colors.white : AppColors.cobaltLight),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].$2,
                              style: const TextStyle(
                                  color: AppColors.screenText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(items[i].$3,
                              style: const TextStyle(
                                  color: AppColors.screenMuted, fontSize: 13)),
                        ],
                      ),
                    ),
                    Text('0${i + 1}',
                        style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            color: AppColors.screenMuted,
                            fontSize: 12)),
                  ],
                ),
              )
                  .animate(delay: (120 * i).ms)
                  .fadeIn(duration: 320.ms)
                  .slideY(begin: 0.15, curve: Curves.easeOutCubic),
              if (i < items.length - 1)
                Container(
                  width: 2,
                  height: 18,
                  color: AppColors.screenBorder,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Step 3: a consent card.
class _ConsentScene extends StatelessWidget {
  const _ConsentScene();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.screenRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.screenBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.cobalt.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.verified_user_rounded,
                  color: AppColors.cobaltLight, size: 26),
            ),
            const SizedBox(height: 18),
            const Text('Consent first',
                style: TextStyle(
                    color: AppColors.screenText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3)),
            const SizedBox(height: 6),
            const Text(
              'Every face on RealFaceAI belongs to someone. We remove content '
              'and close accounts that break these rules.',
              style: TextStyle(
                  color: AppColors.screenMuted, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 18),
            for (final t in const ['Permission for every face', 'No deception or harassment', 'Adults only, 18+'])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: Color(0xFF5BE0AD)),
                    const SizedBox(width: 10),
                    Text(t,
                        style: const TextStyle(
                            color: AppColors.screenText, fontSize: 14)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
