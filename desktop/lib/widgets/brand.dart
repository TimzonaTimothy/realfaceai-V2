import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// Product name and web address, in one place.
abstract class Brand {
  static const String name = 'RealFaceAI';
  static const String domain = 'realfaceai.app';
  static const String url = 'https://realfaceai.app';
  static const String supportEmail = 'support@realfaceai.app';
  static const String tagline = 'Real-time AI face streaming';
}

/// The app icon: the Duet mark (a cobalt face and an outlined AI face whose
/// overlap glows red) on an ink tile.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/icon.svg',
      width: size,
      height: size,
      semanticsLabel: Brand.name,
    );
  }
}

/// Duet mark + "RealFaceAI" wordmark, set in Inter Display: "RealFace" bold,
/// "AI" regular in cobalt.
class BrandLockup extends StatelessWidget {
  final double height;
  final bool onDark;
  const BrandLockup({super.key, this.height = 30, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final fs = height * 0.6;
    final onDark = this.onDark || AppColors.isDark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          onDark ? 'assets/brand/duet-white.svg' : 'assets/brand/duet.svg',
          height: height * 0.62,
          semanticsLabel: Brand.name,
        ),
        SizedBox(width: height * 0.3),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: 'RealFace',
              style: TextStyle(
                  color: onDark ? AppColors.screenText : AppColors.textPrimary),
            ),
            TextSpan(
              text: 'AI',
              style: TextStyle(
                  fontWeight: FontWeight.w400,
                  color: onDark ? AppColors.cobaltLight : AppColors.cobalt),
            ),
          ]),
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: fs,
            fontWeight: FontWeight.w700,
            letterSpacing: -fs * 0.03,
            height: 1,
          ),
        ),
      ],
    );
  }
}
