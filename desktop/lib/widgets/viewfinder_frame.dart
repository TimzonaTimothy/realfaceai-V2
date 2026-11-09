import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

/// Corner brackets around a child, like a camera focus frame.
///
/// This is the app's signature motif. It replaces the old full box border on
/// the few surfaces that matter (the live balance, empty states, the login
/// preview), so use it sparingly — everywhere else uses plain sheets.
class ViewfinderFrame extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? _bracketColor;
  final double arm;
  final double stroke;

  const ViewfinderFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.background,
    Color? bracketColor,
    this.arm = 18,
    this.stroke = 2.5,
  }) : _bracketColor = bracketColor;

  Color get bracketColor => _bracketColor ?? AppColors.cobalt;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BracketPainter(
        color: bracketColor,
        arm: arm,
        stroke: stroke,
      ),
      child: Container(
        color: background,
        padding: padding,
        child: child,
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Color color;
  final double arm;
  final double stroke;

  const _BracketPainter(
      {required this.color, required this.arm, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square;

    final r = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final a = arm.clamp(0, r.shortestSide / 2).toDouble();

    final path = Path()
      // top-left
      ..moveTo(r.left, r.top + a)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + a, r.top)
      // top-right
      ..moveTo(r.right - a, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + a)
      // bottom-right
      ..moveTo(r.right, r.bottom - a)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - a, r.bottom)
      // bottom-left
      ..moveTo(r.left + a, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - a);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color || old.arm != arm || old.stroke != stroke;
}

/// A small pulsing dot — the "on air" light. Static when the OS asks for
/// reduced motion.
class LiveDot extends StatelessWidget {
  final Color? _color;
  final double size;
  final bool pulse;

  const LiveDot({
    super.key,
    Color? color,
    this.size = 8,
    this.pulse = true,
  }) : _color = color;

  Color get color => _color ?? AppColors.tally;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulse || MediaQuery.of(context).disableAnimations) return dot;
    return dot
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fade(begin: 1, end: 0.25, duration: 900.ms, curve: Curves.easeInOut);
  }
}
