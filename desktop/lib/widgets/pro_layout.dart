import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Dense "pro tool" layout primitives shared by Playground, Usage, Billing
/// and Security. Everything is built from the existing Viewfinder tokens
/// (AppColors / AppRadius / AppFonts) — no new colours.
///
/// Anatomy of every redesigned screen:
///
///   ┌ ProToolbar ───────────────────────────────────────────────┐
///   ├──────────────┬───────────────────────────────┬────────────┤
///   │ ProPanel     │ ProPanel (main, own scroll)   │ ProPanel   │
///   │ (rail)       │                               │ (inspector)│
///   └──────────────┴───────────────────────────────┴────────────┘
///
/// The page itself never scrolls; each panel scrolls independently.

/// Breakpoints used by the redesigned screens.
abstract class ProBreakpoints {
  /// Below this the right-hand inspector collapses into the main column.
  static const double inspector = 1100;

  /// Below this the left rail collapses into the main column.
  static const double rail = 800;
}

// ── Page header ────────────────────────────────────────────────────────────

/// The header every page starts with: a large title, a one-line description
/// and the page's actions on the right. (Kept under its old name so existing
/// screens pick up the new look.)
class ProToolbar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget? center;

  const ProToolbar({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final pad = c.maxWidth < 760 ? 16.0 : 28.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, 26, pad, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (center != null) ...[
              const SizedBox(width: 16),
              center!,
            ],
            for (final a in actions) ...[const SizedBox(width: 10), a],
          ],
        ),
      );
    });
  }
}

// ── Panel ──────────────────────────────────────────────────────────────────

/// A white card with a 52px header. When [scroll] is true the body scrolls
/// independently inside the panel.
class ProPanel extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final bool scroll;
  final EdgeInsets padding;
  final Color? color;

  const ProPanel({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.scroll = true,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dark = (color ?? AppColors.bgCard).computeLuminance() < 0.3;
    final edge = dark ? AppColors.screenBorder : AppColors.border;
    final headFg = dark ? AppColors.screenText : AppColors.textPrimary;
    final iconFg = dark ? AppColors.screenMuted : AppColors.textMuted;
    final body = scroll
        ? SingleChildScrollView(padding: padding, child: child)
        : Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: edge),
        boxShadow: dark ? null : AppShadows.xs,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: edge)),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: iconFg),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: headFg,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Lays out rail | main | inspector, degrading gracefully:
///
///   ≥ 1100 px  rail │ main │ inspector
///   ≥  800 px  rail │ main over inspector (inspector gets a fixed height)
///   <  800 px  one scrolling column: rail, main, inspector
///
/// Without a rail, anything under 1100 px is the single scrolling column.
/// Panels in the stacked layouts are given explicit heights because a
/// [ProPanel] scrolls internally and needs bounded space.
class ProWorkspace extends StatelessWidget {
  final Widget? rail;
  final double railWidth;
  final Widget main;
  final Widget? inspector;
  final double inspectorWidth;

  /// Heights used when panels are stacked.
  final double collapsedMainHeight;
  final double collapsedRailHeight;
  final double collapsedInspectorHeight;

  const ProWorkspace({
    super.key,
    required this.main,
    this.rail,
    this.inspector,
    this.railWidth = 300,
    this.inspectorWidth = 300,
    this.collapsedMainHeight = 520,
    this.collapsedRailHeight = 420,
    this.collapsedInspectorHeight = 300,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      const gap = 16.0;
      final side = w < 760 ? 16.0 : 28.0;
      final outer = EdgeInsets.fromLTRB(side, 18, side, 24);
      final hasRail = rail != null;
      final hasInsp = inspector != null;

      // Only a main panel: give it the whole area.
      if (!hasRail && !hasInsp) {
        return Padding(padding: outer, child: main);
      }

      // Wide: three columns.
      if (w >= ProBreakpoints.inspector) {
        return Padding(
          padding: outer,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasRail) ...[
                SizedBox(width: railWidth, child: rail),
                const SizedBox(width: gap),
              ],
              Expanded(child: main),
              if (hasInsp) ...[
                const SizedBox(width: gap),
                SizedBox(width: inspectorWidth, child: inspector),
              ],
            ],
          ),
        );
      }

      // Medium with a rail: rail on the left, inspector tucked under main.
      if (hasRail && w >= ProBreakpoints.rail) {
        return Padding(
          padding: outer,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: railWidth, child: rail),
              const SizedBox(width: gap),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, colConstraints) {
                    final colH = colConstraints.maxHeight;
                    final maxInspH =
                        (colH - 180.0 - gap).clamp(120.0, collapsedInspectorHeight);
                    final inspH = (colH > 0 && colH.isFinite)
                        ? collapsedInspectorHeight.clamp(120.0, maxInspH)
                        : collapsedInspectorHeight;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: main),
                        if (hasInsp) ...[
                          const SizedBox(height: gap),
                          SizedBox(height: inspH, child: inspector),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }

      // Narrow (or medium without a rail): one scrolling column.
      return SingleChildScrollView(
        padding: outer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasRail) ...[
              SizedBox(height: collapsedRailHeight, child: rail),
              const SizedBox(height: gap),
            ],
            SizedBox(height: collapsedMainHeight, child: main),
            if (hasInsp) ...[
              const SizedBox(height: gap),
              SizedBox(height: collapsedInspectorHeight, child: inspector),
            ],
          ],
        ),
      );
    });
  }
}

// ── Small building blocks ──────────────────────────────────────────────────

/// Field / group label. Sentence case, quiet weight.
class ProLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const ProLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = text.isEmpty
        ? text
        : text[0].toUpperCase() + text.substring(1).toLowerCase();
    return Row(
      children: [
        Text(
          t,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.05,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// key → value row with a hairline underneath.
class ProKv extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;
  final bool last;

  const ProKv(
    this.label,
    this.value, {
    super.key,
    this.valueColor,
    this.mono = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: mono ? 13 : 13.5,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? AppFonts.mono : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact stat: label on top, big figure beneath. Used in KPI strips.
class ProStat extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color? color;

  const ProStat({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: color ?? AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

/// A KPI strip: stats separated by hairlines, equal widths.
class ProStatStrip extends StatelessWidget {
  final List<ProStat> stats;
  const ProStatStrip({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.xs,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) Container(width: 1, color: AppColors.border),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: stats[i],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Filter / segmented chip.
class ProChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  const ProChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.cobalt : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.cobalt50 : AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.cobalt200 : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 7),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? AppColors.cobalt100 : AppColors.bgSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: fg,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small status tag (Live, Required, Paid …). Sentence case pill.
class ProTag extends StatelessWidget {
  final String text;
  final Color? _color;
  const ProTag(this.text, {super.key, Color? color}) : _color = color;

  Color get color => _color ?? AppColors.cobalt;

  @override
  Widget build(BuildContext context) {
    final t = text.isEmpty
        ? text
        : text[0].toUpperCase() + text.substring(1).toLowerCase();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        t,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Secondary toolbar button: white, hairline, icon + optional label.
class ProToolButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final String? tooltip;

  const ProToolButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? AppColors.textPrimary : AppColors.textMuted;
    final btn = Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        hoverColor: AppColors.bgHover,
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppShadows.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: enabled ? AppColors.textSecondary : fg),
              if (label != null) ...[
                const SizedBox(width: 8),
                Text(label!,
                    style: TextStyle(
                        color: fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
