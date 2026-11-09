import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';
import '../../utils/error_handler.dart';
import '../../utils/timecode.dart';
import '../../widgets/pro_layout.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/viewfinder_frame.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _dashError;

  // Activity is fetched independently so pagination never reloads the page
  List<dynamic> _activity = [];
  bool _activityLoading = false;
  int _activityPage = 1;
  int _activityTotalPages = 1;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  // Loads everything except activity (chart, ledger, plan).
  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _dashError = null;
    });
    try {
      final data =
          await ApiService.instance.getDashboard(days: 30, activityPage: 1);
      if (!mounted) return;

      final statusCode = data['statusCode'];
      if ((statusCode != null && statusCode != 200) ||
          data.containsKey('error') ||
          data.containsKey('detail')) {
        final errMsg = data['error'] ??
            data['detail'] ??
            'Server returned HTTP $statusCode';
        setState(() {
          _dashError = errMsg.toString();
          _loading = false;
        });
        return;
      }

      _activityTotalPages = data['activity_total_pages'] ?? 1;
      _activityPage = 1;

      // Hoist activity out of _stats so chart/ledger don't depend on it.
      _activity = (data['recent_activity'] as List<dynamic>?) ?? [];

      setState(() {
        _stats = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dashError = ErrorHandler.sanitize(e);
        _loading = false;
      });
    }
  }

  // Fetches only the activity page — no spinner over the whole screen.
  Future<void> _loadActivityPage(int page) async {
    if (!mounted) return;
    setState(() => _activityLoading = true);
    try {
      final data =
          await ApiService.instance.getDashboard(days: 30, activityPage: page);
      if (!mounted) return;
      setState(() {
        _activity = (data['recent_activity'] as List<dynamic>?) ?? [];
        _activityTotalPages = data['activity_total_pages'] ?? 1;
        _activityPage = page;
        _activityLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _activityLoading = false);
    }
  }

  double _parseNum(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 1000;
              final mid = c.maxWidth >= 680;
              final pad = c.maxWidth < 760 ? 16.0 : 28.0;

              final daily = (_stats?['daily_usage'] as List<dynamic>?) ?? [];
              final used = _parseNum(_stats?['total_credits_used']);
              final activeDays =
                  daily.where((e) => _parseNum(e['credits']) > 0).length;

              final monitor = _Monitor(
                credits: auth.credits,
                onTopUp: () => context.go('/billing'),
              ).animate().fadeIn(duration: 280.ms);

              final quickStart = _QuickStart(
                onOpen: () => context.go('/playground'),
              ).animate().fadeIn(duration: 280.ms, delay: 60.ms);

              final kpis = [
                StatCard(
                  label: 'Time streamed',
                  value: CreditDisplay.toTime(used),
                  icon: Icons.timer_outlined,
                  subtitle: 'Last 30 days',
                ),
                StatCard(
                  label: 'Active days',
                  value: '$activeDays',
                  icon: Icons.calendar_today_outlined,
                  subtitle: 'Days with at least one session',
                ),
                StatCard(
                  label: 'Plan',
                  value: _cap((_stats?['plan'] ?? 'free').toString()),
                  icon: Icons.workspace_premium_outlined,
                  subtitle: 'Billed per second of streaming',
                ),
              ];

              final chartCard = _Sheet(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Streaming time per day',
                      subtitle: 'Minutes, last 30 days',
                    ),
                    const SizedBox(height: 24),
                    SizedBox(height: 240, child: _buildChart()),
                  ],
                ),
              );

              final activityCard = _Sheet(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: 'Recent activity',
                      action: TextButton(
                        onPressed: () => context.go('/usage'),
                        child: const Text('View all'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildActivityList(),
                  ],
                ),
              );

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 26, pad, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(auth, compact: !mid),
                    if (_dashError != null) ...[
                      const SizedBox(height: 16),
                      _errorBanner(),
                    ],
                    const SizedBox(height: 24),
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 3, child: monitor),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: quickStart),
                          ],
                        ),
                      )
                    else ...[
                      monitor,
                      const SizedBox(height: 16),
                      quickStart,
                    ],
                    const SizedBox(height: 16),
                    if (mid)
                      Row(
                        children: [
                          for (var i = 0; i < kpis.length; i++) ...[
                            if (i > 0) const SizedBox(width: 16),
                            Expanded(child: kpis[i]),
                          ],
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final k in kpis) ...[
                            k,
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: chartCard),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: activityCard),
                        ],
                      )
                    else ...[
                      chartCard,
                      const SizedBox(height: 16),
                      activityCard,
                    ],
                  ],
                ),
              );
            }),
    );
  }

  Widget _header(AuthProvider auth, {required bool compact}) {
    final name = auth.user?.username ?? '';
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? _greeting() : '${_greeting()}, $name',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Here’s your streaming time and what you’ve been working on.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProToolButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh',
          onPressed: _loadStats,
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => context.go('/playground'),
          icon: const Icon(Icons.videocam_outlined, size: 18),
          label: const Text('New live session'),
        ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 16), actions],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [Expanded(child: title), actions],
    );
  }

  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
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
              _dashError!,
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 13.5, height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: _loadStats, child: const Text('Try again')),
        ],
      ),
    );
  }

  // Daily bars. Minutes rather than raw credits, because everything else in
  // the app talks about time. The most recent day is the solid bar.
  Widget _buildChart() {
    final daily = (_stats?['daily_usage'] as List<dynamic>?) ?? [];
    if (daily.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'No usage yet',
        subtitle: 'Daily streaming time appears here after your first session.',
      );
    }

    final minutes = daily
        .map((e) =>
            _parseNum(e['credits'] ?? 0) * 0.5 / 60.0) // 1 credit = 0.5 s
        .toList();

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < minutes.length; i++) {
      final isLast = i == minutes.length - 1;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: minutes[i],
              width: 8,
              color: isLast ? AppColors.cobalt : AppColors.cobalt200,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xs)),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        backgroundColor: Colors.transparent,
        barGroups: groups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.border, strokeWidth: 1, dashArray: [3, 4]),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (val, meta) => Text(
                val == meta.max ? '' : val.toInt().toString(),
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontFamily: AppFonts.mono),
              ),
            ),
          ),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildActivityList() {
    if (_activity.isEmpty && !_activityLoading) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'No activity yet',
        subtitle: 'Start a session in the playground and it will show up here.',
      );
    }

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _activityLoading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  height: 8 * 52.0, // keeps card height stable
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Column(
                  key: const ValueKey('rows'),
                  children: _activity.take(8).map((item) {
                    final endpoint = item['endpoint'] as String? ?? '';
                    final credits = _parseNum(item['credits_used']);

                    IconData icon;
                    Color color;
                    String label;
                    switch (endpoint) {
                      case 'realtime_token':
                        icon = Icons.stream_rounded;
                        color = AppColors.cobalt;
                        label = 'Realtime stream';
                        break;
                      case 'queue_video':
                        icon = Icons.videocam_outlined;
                        color = AppColors.success;
                        label = 'Video generation';
                        break;
                      default:
                        icon = Icons.image_outlined;
                        color = AppColors.warning;
                        label = 'Image generation';
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        children: [
                          Icon(icon, color: color, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label,
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          Text(
                            CreditDisplay.toTime(credits),
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        if (_activityTotalPages > 1) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PagBtn(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous page',
                enabled: _activityPage > 1 && !_activityLoading,
                onTap: () => _loadActivityPage(_activityPage - 1),
              ),
              const SizedBox(width: 12),
              Text(
                'Page $_activityPage of $_activityTotalPages',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 12),
              _PagBtn(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next page',
                enabled:
                    _activityPage < _activityTotalPages && !_activityLoading,
                onTap: () => _loadActivityPage(_activityPage + 1),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Sheet: flat panel ─────────────────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  final Widget child;
  const _Sheet({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.xs,
      ),
      child: child,
    );
  }
}

// ── Pagination button ─────────────────────────────────────────────────────────

class _PagBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _PagBtn({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? AppColors.textPrimary
                : AppColors.textMuted.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

// ── The monitor: balance as timecode ──────────────────────────────────────────
//
// The page's one memorable element. A dark screen with focus brackets,
// showing remaining streaming time the way a camera does. When the balance is
// low the brackets and digits turn tally-red and the on-air dot pulses.

class _Monitor extends StatelessWidget {
  final double credits;
  final VoidCallback onTopUp;
  const _Monitor({required this.credits, required this.onTopUp});

  @override
  Widget build(BuildContext context) {
    final low = credits < 100;
    final code = Timecode.fromCreditsString(credits);
    final tone = low ? const Color(0xFFFF8A84) : AppColors.screenText;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.screen,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.9, -1),
                  radius: 1.3,
                  colors: [Color(0x403A3DFF), Color(0x000F1117)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ViewfinderFrame(
              bracketColor: low ? AppColors.tally : AppColors.cobaltLight,
              arm: 20,
              stroke: 2.5,
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (low) ...[
                        const LiveDot(),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        low ? 'Streaming time is low' : 'Streaming time left',
                        style: const TextStyle(
                            color: AppColors.screenMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      label:
                          'Streaming time left ${CreditDisplay.toTime(credits)}',
                      child: Text(
                        code,
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          color: tone,
                          fontSize: 60,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -2,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'hours · minutes · seconds',
                    style: TextStyle(
                      color: AppColors.screenMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: onTopUp,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Top up'),
                      ),
                      Text(
                        low
                            ? 'Add time before your next session.'
                            : 'You’re only charged while a stream is live.',
                        style: const TextStyle(
                            color: AppColors.screenMuted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick start: the three steps to a live session ─────────────────────────────

class _QuickStart extends StatelessWidget {
  final VoidCallback onOpen;
  const _QuickStart({required this.onOpen});

  static const _steps = [
    (Icons.add_photo_alternate_outlined, 'Choose a face photo',
        'Clear, front-facing, good light'),
    (Icons.play_circle_outline_rounded, 'Launch the studio',
        'Allow camera access when asked'),
    (Icons.cast_rounded, 'Send to OBS or your call',
        'Use it as a browser source'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Go live in three steps',
            subtitle: 'Everything happens in the studio',
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.cobalt50,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(_steps[i].$1, size: 18, color: AppColors.cobalt),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_steps[i].$2,
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        Text(_steps[i].$3,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Open the studio'),
            ),
          ),
        ],
      ),
    );
  }
}