import 'package:flutter/material.dart';

/// RealFaceAI design system.
///
/// One accent (cobalt) for actions, focus and selection; one signal colour
/// (tally red) for anything live, low or destructive; one dark "monitor"
/// surface for the things that are live. Everything else is a calm, cool
/// neutral so the product's own video is the loudest thing on screen.
///
/// Token NAMES are stable so every screen picks up changes automatically.
/// The `gold*` names are legacy aliases that resolve to cobalt; new code
/// should use `cobalt*`.
///
/// Neutral and wash tokens are getters that follow the active palette
/// ([isDark], set by `ThemeController`), so they can't be used in `const`
/// expressions. The monitor (`screen*`) is dark in both palettes.
abstract class AppColors {
  /// Which palette the getters below resolve to. Only `ThemeController`
  /// should change this.
  static bool isDark = false;

  static Color _pick(Color light, Color dark) => isDark ? dark : light;

  // ── Accent: cobalt (actions, focus, selection) ───────────────────────────
  // Brightened on dark so cobalt text and icons keep their contrast.
  static Color get cobalt =>
      _pick(const Color(0xFF3A3DFF), const Color(0xFF6366FF));
  static const Color cobaltLight = Color(0xFF7B7EFF);
  static const Color cobaltDark = Color(0xFF2327D1);
  static const Color cobaltWash = Color(0x1A3A3DFF); // 10%
  static Color get cobalt50 =>
      _pick(const Color(0xFFF1F1FF), const Color(0xFF1C1E40));
  static Color get cobalt100 =>
      _pick(const Color(0xFFE2E3FF), const Color(0xFF262A5C));
  static Color get cobalt200 =>
      _pick(const Color(0xFFC4C5FF), const Color(0xFF353A8C));

  // ── Live signal: tally red (recording, low balance, errors) ──────────────
  static Color get tally =>
      _pick(const Color(0xFFE5322D), const Color(0xFFFF5A52));
  static Color get tallyWash =>
      _pick(const Color(0xFFFDECEC), const Color(0xFF3A1715));

  /// Error copy on a page surface (stronger than [tally] for small text).
  static Color get dangerText =>
      _pick(const Color(0xFFB4231F), const Color(0xFFFF8A84));

  // ── Legacy aliases (do not use in new code) ──────────────────────────────
  static Color get gold => cobalt;
  static const Color goldLight = cobaltLight;
  static const Color goldDark = cobaltDark;
  static const Color goldGlow = cobaltWash;
  static Color get textGold => cobalt;

  // ── Surfaces ─────────────────────────────────────────────────────────────
  static Color get bg => // app canvas
      _pick(const Color(0xFFF3F4F8), const Color(0xFF0B0D12));
  static Color get bgCard => // cards, panels, sidebar
      _pick(const Color(0xFFFFFFFF), const Color(0xFF14161D));
  static Color get bgSubtle => // table heads, wells
      _pick(const Color(0xFFF7F8FB), const Color(0xFF181B23));
  static Color get bgElevated => // popovers, dialogs
      _pick(const Color(0xFFFFFFFF), const Color(0xFF1C1F28));
  static Color get bgInput =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF101218));
  static Color get bgHover =>
      _pick(const Color(0xFFEDEFF4), const Color(0xFF20242E));

  // ── The monitor: the one dark surface, reserved for live things ──────────
  static const Color screen = Color(0xFF0F1117);
  static const Color screenRaised = Color(0xFF1B1E28);
  static const Color screenBorder = Color(0xFF272B37);
  static const Color screenText = Color(0xFFF2F4F8);
  static const Color screenMuted = Color(0xFF8A91A3);

  // ── Lines ────────────────────────────────────────────────────────────────
  static Color get border =>
      _pick(const Color(0xFFE2E5EC), const Color(0xFF262A35));
  static Color get borderLight => // stronger hairline
      _pick(const Color(0xFFCDD2DC), const Color(0xFF353A47));
  static Color get borderHover =>
      _pick(const Color(0xFFB5BCCA), const Color(0xFF474D5C));

  // ── Text (all pass 4.5:1 on their page surfaces) ─────────────────────────
  static Color get textPrimary =>
      _pick(const Color(0xFF12141C), const Color(0xFFF2F4F8));
  static Color get textSecondary =>
      _pick(const Color(0xFF4C5466), const Color(0xFFB2B8C6));
  static Color get textMuted =>
      _pick(const Color(0xFF687085), const Color(0xFF8C93A5));

  // ── Semantic ─────────────────────────────────────────────────────────────
  static Color get success =>
      _pick(const Color(0xFF0B8A5F), const Color(0xFF34C58F));
  static Color get successWash =>
      _pick(const Color(0xFFE7F6F0), const Color(0xFF0F2A21));
  static Color get danger => tally;
  static Color get info =>
      _pick(const Color(0xFF0B6FC2), const Color(0xFF4AA3F0));
  static Color get warning =>
      _pick(const Color(0xFFB86E00), const Color(0xFFF0A23B));
  static Color get warningWash =>
      _pick(const Color(0xFFFFF4E0), const Color(0xFF33240A));

  // Alias used in main.dart splash
  static Color get accent => cobalt;

  /// Brand gradient used by the logo tile and primary hero surfaces.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5457FF), cobaltDark],
  );
}

/// Shape scale. Soft but precise.
abstract class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

/// 4-pt spacing scale.
abstract class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double page = 32;
}

/// Elevation is expressed with soft, cool shadows rather than Material tint.
abstract class AppShadows {
  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0A12141C), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0F12141C), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0812141C), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1412141C), blurRadius: 32, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0A12141C), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// The focus halo drawn around inputs and focused controls.
  static List<BoxShadow> focus([Color? color]) => [
        BoxShadow(
            color: (color ?? AppColors.cobalt).withValues(alpha: 0.16),
            spreadRadius: 4),
      ];
}

/// Font families, bundled in assets/fonts (see pubspec.yaml).
abstract class AppFonts {
  static const String ui = 'Inter';
  static const String display = 'InterDisplay';
  static const String mono = 'JetBrainsMono';
}

// ── AppTheme ──────────────────────────────────────────────────────────────
abstract class AppTheme {
  static const _radiusSm = BorderRadius.all(Radius.circular(AppRadius.sm));

  static OutlineInputBorder _inputBorder(Color c, [double w = 1]) =>
      OutlineInputBorder(
        borderRadius: _radiusSm,
        borderSide: BorderSide(color: c, width: w),
      );

  /// Theme for the palette currently selected in [AppColors.isDark].
  static ThemeData get current => _build();

  static ThemeData _build() => ThemeData(
        useMaterial3: true,
        brightness: AppColors.isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.cobalt,
          brightness: AppColors.isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: AppColors.cobalt,
          secondary: AppColors.cobaltLight,
          surface: AppColors.bgCard,
          error: AppColors.tally,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.textPrimary,
          onError: Colors.white,
          outline: AppColors.border,
          outlineVariant: AppColors.border,
        ),
        fontFamily: AppFonts.ui,
        visualDensity: VisualDensity.standard,
        splashFactory: InkRipple.splashFactory,
        focusColor: AppColors.cobaltWash,
        hoverColor: AppColors.bgHover,
        highlightColor: Colors.transparent,

        // ── AppBar ───────────────────────────────────────────────────────────
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: AppFonts.ui,
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: AppColors.textSecondary),
        ),

        // ── Cards: white sheets, hairline edge ──────────────────────────────
        cardTheme: CardThemeData(
          color: AppColors.bgCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
            side: BorderSide(color: AppColors.border, width: 1),
          ),
          margin: EdgeInsets.zero,
        ),

        // ── Dialogs / menus / tooltips ──────────────────────────────────────
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.bgElevated,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shadowColor: Color(0x3312141C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
          ),
          titleTextStyle: TextStyle(
            fontFamily: AppFonts.ui,
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          contentTextStyle: TextStyle(
            fontFamily: AppFonts.ui,
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: AppColors.bgElevated,
          surfaceTintColor: Colors.transparent,
          elevation: 10,
          shadowColor: Color(0x3312141C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
            side: BorderSide(color: AppColors.border),
          ),
          textStyle: TextStyle(
              fontFamily: AppFonts.ui,
              color: AppColors.textPrimary,
              fontSize: 13.5),
        ),
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 400),
          decoration: BoxDecoration(
            color: AppColors.screen,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          ),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          textStyle: TextStyle(
              fontFamily: AppFonts.ui,
              color: AppColors.screenText,
              fontSize: 12,
              fontWeight: FontWeight.w500),
        ),

        // ── Text selection ──────────────────────────────────────────────────
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.cobalt,
          selectionColor: AppColors.cobalt100,
          selectionHandleColor: AppColors.cobalt,
        ),

        // ── Input fields: white wells, crisp hairline, cobalt focus ─────────
        // Labels are rendered above the field by [AppTextField]; fields that
        // still pass `labelText` get a non-floating, hint-style label.
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bgInput,
          hoverColor: Colors.transparent,
          isDense: true,
          hintStyle: TextStyle(
              color: AppColors.isDark
                  ? const Color(0xFF6E7588)
                  : const Color(0xFF8E95A6),
              fontSize: 14,
              height: 1.4),
          labelStyle:
              TextStyle(color: AppColors.textMuted, fontSize: 14),
          floatingLabelStyle: TextStyle(
              color: AppColors.cobalt,
              fontSize: 13,
              fontWeight: FontWeight.w500),
          helperStyle:
              TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          errorStyle: TextStyle(
              color: AppColors.tally, fontSize: 12.5, height: 1.3),
          prefixIconColor: WidgetStateColor.resolveWith((s) =>
              s.contains(WidgetState.focused)
                  ? AppColors.cobalt
                  : AppColors.textMuted),
          suffixIconColor: AppColors.textMuted,
          prefixIconConstraints:
              const BoxConstraints(minWidth: 42, minHeight: 20),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 42, minHeight: 20),
          border: _inputBorder(AppColors.borderLight),
          enabledBorder: _inputBorder(AppColors.borderLight),
          disabledBorder: _inputBorder(AppColors.border),
          focusedBorder: _inputBorder(AppColors.cobalt, 1.5),
          errorBorder: _inputBorder(AppColors.tally),
          focusedErrorBorder: _inputBorder(AppColors.tally, 1.5),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),

        // ── Buttons ──────────────────────────────────────────────────────────
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((s) {
              if (s.contains(WidgetState.disabled)) {
                return AppColors.cobalt.withValues(alpha: 0.35);
              }
              if (s.contains(WidgetState.pressed)) return AppColors.cobaltDark;
              if (s.contains(WidgetState.hovered)) {
                return const Color(0xFF2E31F0);
              }
              return AppColors.cobalt;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.disabled)
                    ? Colors.white70
                    : Colors.white),
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            elevation: WidgetStateProperty.all(0),
            minimumSize: WidgetStateProperty.all(const Size(64, 42)),
            padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
            textStyle: WidgetStateProperty.all(const TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            )),
            shape: WidgetStateProperty.all(
                const RoundedRectangleBorder(borderRadius: _radiusSm)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.cobalt,
            foregroundColor: Colors.white,
            minimumSize: const Size(64, 42),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            textStyle: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            shape: const RoundedRectangleBorder(borderRadius: _radiusSm),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.cobalt,
            shape: const RoundedRectangleBorder(borderRadius: _radiusSm),
            textStyle: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            backgroundColor: AppColors.bgCard,
            side: BorderSide(color: AppColors.borderLight, width: 1),
            minimumSize: const Size(64, 42),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            textStyle: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            shape: const RoundedRectangleBorder(borderRadius: _radiusSm),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            shape: const RoundedRectangleBorder(borderRadius: _radiusSm),
          ),
        ),

        listTileTheme: ListTileThemeData(
          tileColor: Colors.transparent,
          textColor: AppColors.textPrimary,
          iconColor: AppColors.textSecondary,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: _radiusSm),
        ),

        dividerTheme: DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 0,
        ),

        // ── Chip ─────────────────────────────────────────────────────────────
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.bgCard,
          selectedColor: AppColors.cobalt50,
          disabledColor: AppColors.bgSubtle,
          labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          secondaryLabelStyle:
              TextStyle(color: AppColors.cobalt, fontSize: 12.5),
          side: BorderSide(color: AppColors.border, width: 1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),

        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: AppColors.bgCard,
          selectedIconTheme: IconThemeData(color: AppColors.cobalt, size: 20),
          unselectedIconTheme:
              IconThemeData(color: AppColors.textMuted, size: 20),
          indicatorColor: AppColors.cobalt50,
        ),

        drawerTheme: DrawerThemeData(
          backgroundColor: AppColors.bgCard,
          elevation: 0,
        ),

        // ── SnackBar: dark monitor toast on a light page ────────────────────
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.screen,
          contentTextStyle: TextStyle(
              fontFamily: AppFonts.ui,
              color: AppColors.screenText,
              fontSize: 13.5),
          actionTextColor: AppColors.cobaltLight,
          shape: RoundedRectangleBorder(borderRadius: _radiusSm),
          behavior: SnackBarBehavior.floating,
          width: 420,
        ),

        // ── Tab Bar ──────────────────────────────────────────────────────────
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.cobalt,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 13.5,
              fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 13.5,
              fontWeight: FontWeight.w500),
          dividerColor: AppColors.border,
        ),

        iconTheme:
            IconThemeData(color: AppColors.textSecondary, size: 20),

        scrollbarTheme: ScrollbarThemeData(
          thickness: WidgetStateProperty.all(6),
          radius: const Radius.circular(AppRadius.pill),
          thumbColor: WidgetStateProperty.all(AppColors.isDark
              ? const Color(0x33F2F4F8)
              : const Color(0x3312141C)),
        ),

        // ── Type scale ───────────────────────────────────────────────────────
        // Display sizes use Inter Display (tighter, built for large sizes);
        // everything from 18 px down uses Inter text.
        textTheme: TextTheme(
          displayLarge: TextStyle(
              fontFamily: AppFonts.display,
              color: AppColors.textPrimary,
              fontSize: 44,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.4,
              height: 1.08),
          displayMedium: TextStyle(
              fontFamily: AppFonts.display,
              color: AppColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.9,
              height: 1.15),
          displaySmall: TextStyle(
              fontFamily: AppFonts.display,
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.2),
          headlineLarge: TextStyle(
              fontFamily: AppFonts.display,
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              height: 1.25),
          headlineMedium: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3),
          headlineSmall: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2),
          titleLarge: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2),
          titleMedium: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1),
          titleSmall: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.55),
          bodyMedium: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.5),
          bodySmall: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              height: 1.45),
          labelLarge: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600),
          labelMedium: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500),
          labelSmall: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500),
        ),

        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: AppColors.cobalt,
          linearTrackColor: AppColors.cobalt100,
          circularTrackColor: Colors.transparent,
        ),

        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? Colors.white
                  : AppColors.textMuted),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AppColors.cobalt
                  : AppColors.border),
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        ),

        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AppColors.cobalt
                  : AppColors.bgInput),
          checkColor: WidgetStateProperty.all(Colors.white),
          side: WidgetStateBorderSide.resolveWith((s) => BorderSide(
              color: s.contains(WidgetState.selected)
                  ? AppColors.cobalt
                  : AppColors.borderLight,
              width: 1.5)),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs))),
        ),

        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AppColors.cobalt
                  : AppColors.borderLight),
        ),
      );

  /// Kept so `theme: AppTheme.light` / `AppTheme.dark` still compile. Both
  /// return the active palette; switch palettes through `ThemeController`.
  static ThemeData get light => current;
  static ThemeData get dark => current;
}

// ── Reusable widget helpers (API unchanged) ──────────────────────────────

/// A white sheet with a hairline edge and a whisper of shadow.
class BnCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;

  const BnCard(
      {super.key, required this.child, this.padding, this.color, this.onTap});

  @override
  State<BnCard> createState() => _BnCardState();
}

class _BnCardState extends State<BnCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: widget.color ?? AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: interactive && _hover
                ? AppColors.borderLight
                : AppColors.border),
        boxShadow: interactive && _hover ? AppShadows.sm : AppShadows.xs,
      ),
      padding: widget.padding ?? const EdgeInsets.all(20),
      child: widget.child,
    );
    if (!interactive) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}

/// Small tag. Sentence case, tinted fill.
class BnBadge extends StatelessWidget {
  final String label;
  final Color? bg;
  final Color? fg;

  const BnBadge(this.label, {super.key, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? AppColors.cobalt50,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg ?? AppColors.cobalt,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Status dot + text
class BnStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const BnStatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Section header — a plain heading with an optional trailing widget.
class BnSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const BnSectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      if (trailing != null) ...[const Spacer(), trailing!],
    ]);
  }
}

/// Stat card — label above, large figure below.
class BnStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final IconData? icon;
  final Color? accentColor;
  final Widget? trailing;

  const BnStatCard({
    super.key,
    required this.label,
    required this.value,
    this.subValue,
    this.icon,
    this.accentColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor;
    return BnCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, color: color ?? AppColors.textMuted, size: 16),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 12),
        Text(value,
            style: TextStyle(
                fontFamily: AppFonts.display,
                color: color ?? AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6)),
        if (subValue != null) ...[
          const SizedBox(height: 4),
          Text(subValue!,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ],
      ]),
    );
  }
}
