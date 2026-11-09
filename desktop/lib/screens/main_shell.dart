import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';
import '../services/theme_controller.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/timecode.dart';
import '../widgets/account_status_banner.dart';
import '../widgets/brand.dart';
import '../widgets/update_banner.dart';
import '../widgets/viewfinder_frame.dart';

/// App frame.
///
///   ┌ Sidebar ──────┬ Page ─────────────────────────────────────────┐
///   │ logo          │ header (title · description · actions)       │
///   │ Workspace     │                                              │
///   │  Dashboard    │ content                                      │
///   │  Studio       │                                              │
///   │  Usage        │                                              │
///   │ Account       │                                              │
///   │  Billing      │                                              │
///   │  Security     │                                              │
///   │               │                                              │
///   │ [time left]   │                                              │
///   │ (D) David  ⋯  │                                              │
///   └───────────────┴──────────────────────────────────────────────┘
///
/// ≥ 1180 px: full sidebar with labels.
/// 760–1180 px: icon rail (labels in tooltips).
/// < 760 px: no sidebar; a compact top bar and a bottom tab bar.
class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    // Normally already started from main(); idempotent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.instance.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isStudio = location.startsWith('/playground');

    return ChangeNotifierProvider<UpdateService>.value(
      value: UpdateService.instance,
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 760;
        final rail = !narrow && c.maxWidth < 1180;

        // The studio needs the full width; every other page reads better in
        // a centred column.
        final page = isStudio
            ? widget.child
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: widget.child,
                ),
              );

        // Frozen accounts get a notice above every page.
        final framed = Column(
          children: [
            const AccountStatusBanner(),
            Expanded(child: page),
          ],
        );

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Stack(
            children: [
              if (narrow)
                Column(
                  children: [
                    const _CompactTopBar(),
                    Expanded(child: framed),
                    _BottomNav(location: location),
                  ],
                )
              else
                Row(
                  children: [
                    _Sidebar(location: location, collapsed: rail),
                    Expanded(child: framed),
                  ],
                ),
              // Update notice floats over the page.
              Positioned(
                right: 20,
                bottom: narrow ? 84 : 20,
                width: 320,
                child: const UpdateBanner(),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Navigation model ──────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final IconData iconActive;
  final String label;
  final String route;
  const _NavItem(this.icon, this.iconActive, this.label, this.route);
}

const _workspace = [
  _NavItem(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded,
      'Dashboard', '/dashboard'),
  _NavItem(Icons.center_focus_strong_outlined,
      Icons.center_focus_strong_rounded, 'Studio', '/playground'),
  _NavItem(Icons.insights_outlined, Icons.insights_rounded, 'Usage', '/usage'),
];

const _account = [
  _NavItem(Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded, 'Billing', '/billing'),
  _NavItem(Icons.shield_outlined, Icons.shield_rounded, 'Security',
      '/change-password'),
];

const _allNav = [..._workspace, ..._account];

String _cap(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

bool _isActive(String location, String route) =>
    location == route || location.startsWith('$route/');

// ── Sidebar ───────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final String location;
  final bool collapsed;
  const _Sidebar({required this.location, required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final w = collapsed ? 76.0 : 256.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: w,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      clipBehavior: Clip.hardEdge,
      // Lay out at the target width so the content never overflows while the
      // width animates; the container clips it instead.
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: w,
        maxWidth: w,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand
            SizedBox(
              height: 72,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 20),
                child: Align(
                  alignment:
                      collapsed ? Alignment.center : Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => context.go('/dashboard'),
                    child: collapsed
                        ? const BrandMark(size: 34)
                        : const BrandLockup(height: 30),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                    horizontal: collapsed ? 14 : 12, vertical: 6),
                children: [
                  _SectionLabel('Workspace', collapsed: collapsed),
                  for (final item in _workspace)
                    _SideNavTile(
                      item: item,
                      active: _isActive(location, item.route),
                      collapsed: collapsed,
                    ),
                  const SizedBox(height: 18),
                  _SectionLabel('Account', collapsed: collapsed),
                  for (final item in _account)
                    _SideNavTile(
                      item: item,
                      active: _isActive(location, item.route),
                      collapsed: collapsed,
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  collapsed ? 12 : 12, 0, collapsed ? 12 : 12, 12),
              child: _BalanceCard(collapsed: collapsed),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 0 : 12, vertical: 10),
              child: _AccountMenu(collapsed: collapsed),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool collapsed;
  const _SectionLabel(this.text, {required this.collapsed});

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: Divider(),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _SideNavTile extends StatefulWidget {
  final _NavItem item;
  final bool active;
  final bool collapsed;
  const _SideNavTile({
    required this.item,
    required this.active,
    required this.collapsed,
  });

  @override
  State<_SideNavTile> createState() => _SideNavTileState();
}

class _SideNavTileState extends State<_SideNavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final fg = active
        ? AppColors.cobalt
        : _hover
            ? AppColors.textPrimary
            : AppColors.textSecondary;
    final bg = active
        ? AppColors.cobalt50
        : _hover
            ? AppColors.bgHover
            : Colors.transparent;

    final tile = Semantics(
      button: true,
      selected: active,
      label: widget.item.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => context.go(widget.item.route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            height: 40,
            margin: const EdgeInsets.only(bottom: 2),
            padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(active ? widget.item.iconActive : widget.item.icon,
                    size: 19, color: fg),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: TextStyle(
                        color: active ? AppColors.cobalt : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  if (active)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: AppColors.cobalt, shape: BoxShape.circle),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return widget.collapsed
        ? Tooltip(
            message: widget.item.label,
            preferBelow: false,
            verticalOffset: 0,
            margin: const EdgeInsets.only(left: 76),
            child: tile)
        : tile;
  }
}

/// Remaining streaming time on the dark "monitor" surface. Tapping tops up.
class _BalanceCard extends StatelessWidget {
  final bool collapsed;
  const _BalanceCard({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final credits = context.watch<AuthProvider>().credits;
    final low = credits < 100;
    final code = Timecode.fromCreditsString(credits);
    final tone = low ? const Color(0xFFFF8A84) : AppColors.screenText;

    if (collapsed) {
      return Tooltip(
        message: 'Time left $code. Top up',
        child: Material(
          color: AppColors.screen,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => context.go('/billing'),
            child: SizedBox(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  low
                      ? const LiveDot()
                      : const Icon(Icons.timer_outlined,
                          size: 16, color: AppColors.cobaltLight),
                  const SizedBox(height: 4),
                  Text(
                    code.substring(0, code.length - 3),
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      color: tone,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.screen,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (low) ...[const LiveDot(), const SizedBox(width: 8)],
              Text(
                low ? 'Time is running low' : 'Streaming time left',
                style: const TextStyle(
                  color: AppColors.screenMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            code,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              color: tone,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/billing'),
              style: ButtonStyle(
                minimumSize: WidgetStateProperty.all(const Size(0, 36)),
                padding: WidgetStateProperty.all(EdgeInsets.zero),
                textStyle: WidgetStateProperty.all(const TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
              ),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Top up'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initial;
  static const double size = 34;
  const _Avatar(this.initial);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  final bool collapsed;
  const _AccountMenu({this.collapsed = false});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final name = user?.username ?? '';
    final email = user?.email ?? '';
    final plan = _cap(user?.plan ?? 'free');
    final initial =
        (name.isNotEmpty ? name : (email.isNotEmpty ? email : 'U'))[0]
            .toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.over,
      offset: const Offset(0, -330),
      onSelected: (v) async {
        final router = GoRouter.of(context);
        if (v == 'out') {
          await auth.logout();
          router.go('/login');
        } else if (v == 'security') {
          router.go('/change-password');
        } else if (v == 'billing') {
          router.go('/billing');
        } else if (v.startsWith('theme:')) {
          final mode = ThemeMode.values.byName(v.substring(6));
          ThemeController.instance.setMode(mode);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              if (email.isNotEmpty)
                Text(email,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 8),
              BnBadge('$plan plan'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        _menuItem('billing', Icons.account_balance_wallet_outlined,
            'Billing and top up'),
        _menuItem('security', Icons.shield_outlined, 'Password and security'),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          enabled: false,
          height: 30,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Appearance',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        _themeItem(ThemeMode.system, Icons.desktop_windows_outlined, 'System'),
        _themeItem(ThemeMode.light, Icons.light_mode_outlined, 'Light'),
        _themeItem(ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
        const PopupMenuDivider(height: 1),
        _menuItem('out', Icons.logout_rounded, 'Sign out',
            color: AppColors.tally),
      ],
      child: collapsed
          ? Center(child: _Avatar(initial))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  _Avatar(initial),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name.isEmpty ? 'Account' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$plan plan',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.unfold_more_rounded,
                      size: 18, color: AppColors.textMuted),
                ],
              ),
            ),
    );
  }

  PopupMenuItem<String> _themeItem(ThemeMode mode, IconData icon, String label) {
    final selected = ThemeController.instance.mode == mode;
    return PopupMenuItem<String>(
      value: 'theme:${mode.name}',
      height: 38,
      child: Row(
        children: [
          Icon(icon,
              size: 17,
              color: selected ? AppColors.cobalt : AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ),
          if (selected)
            Icon(Icons.check_rounded, size: 17, color: AppColors.cobalt),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {Color? color}) {
    color ??= AppColors.textPrimary;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon,
              size: 17,
              color: color == AppColors.textPrimary
                  ? AppColors.textSecondary
                  : color),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 13.5, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Narrow windows ────────────────────────────────────────────────────────────

class _CompactTopBar extends StatelessWidget {
  const _CompactTopBar();

  @override
  Widget build(BuildContext context) {
    final credits = context.watch<AuthProvider>().credits;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const BrandLockup(height: 26),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: () => context.go('/billing'),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.screen,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              alignment: Alignment.center,
              child: Text(
                Timecode.fromCreditsString(credits),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  color: AppColors.screenText,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const SizedBox(width: 40, child: _AccountMenu(collapsed: true)),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final String location;
  const _BottomNav({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: _allNav.map((item) {
              final active = _isActive(location, item.route);
              final color = active ? AppColors.cobalt : AppColors.textMuted;
              return Expanded(
                child: InkWell(
                  onTap: () => context.go(item.route),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(active ? item.iconActive : item.icon,
                          size: 22, color: color),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
