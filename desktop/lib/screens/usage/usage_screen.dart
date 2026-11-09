import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';
import '../../widgets/pro_layout.dart';
import '../../widgets/shared_widgets.dart';

/// Usage — dense log viewer.
///
///   Toolbar (title · refresh)
///   ┌ Log table (filters, sticky header, pinned pager) ┬ Summary ┐
///
/// The page never scrolls: the table body scrolls, the pager stays pinned.
class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  List<dynamic> _logs = [];
  bool _loading = true;
  String? _filter; // endpoint key, null = all

  static const int _pageSize = 25;
  int _page = 0;

  // ── Data ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.instance.getUsageHistory();
      if (!mounted) return;
      setState(() {
        _logs = data;
        _page = 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  static double _credits(dynamic log) {
    final raw = (log as Map<String, dynamic>)['credits_used'];
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  static String _endpoint(dynamic log) =>
      (log as Map<String, dynamic>)['endpoint'] as String? ?? '';

  List<dynamic> get _filtered => _filter == null
      ? _logs
      : _logs.where((l) => _endpoint(l) == _filter).toList();

  int get _totalPages => (_filtered.length / _pageSize).ceil().clamp(1, 9999);

  List<dynamic> get _pageLogs {
    final f = _filtered;
    final start = (_page * _pageSize).clamp(0, f.length);
    final end = (start + _pageSize).clamp(0, f.length);
    return f.sublist(start, end);
  }

  String _label(String e) {
    switch (e) {
      case 'realtime_token':
        return 'Realtime stream';
      case 'queue_video':
        return 'Video generation';
      case 'queue_image':
        return 'Image generation';
      default:
        if (e.isEmpty) return 'Unknown';
        final t = e.replaceAll('_', ' ');
        return t[0].toUpperCase() + t.substring(1);
    }
  }

  IconData _icon(String e) {
    switch (e) {
      case 'realtime_token':
        return Icons.stream_rounded;
      case 'queue_video':
        return Icons.videocam_rounded;
      default:
        return Icons.image_rounded;
    }
  }

  Color _color(String e) {
    switch (e) {
      case 'realtime_token':
        return AppColors.cobalt;
      case 'queue_video':
        return AppColors.success;
      default:
        return AppColors.warning;
    }
  }

  String _ts(String ts) =>
      ts.length > 16 ? ts.substring(0, 16).replaceAll('T', ' ') : ts;

  void _setFilter(String? f) => setState(() {
        _filter = f;
        _page = 0;
      });

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          ProToolbar(
            icon: Icons.history_rounded,
            title: 'Usage',
            subtitle: 'Every session on your account, with the time it used.',
            actions: [
              ProToolButton(
                icon: Icons.refresh_rounded,
                label: 'Refresh',
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                        color: AppColors.cobalt, strokeWidth: 2),
                  )
                : _logs.isEmpty
                    ? const EmptyState(
                        icon: Icons.history_rounded,
                        title: 'No usage yet',
                        subtitle:
                            'Sessions will appear here once you start streaming',
                      )
                    : ProWorkspace(
                        main: _tablePanel(),
                        inspector: _summaryPanel(),
                        inspectorWidth: 320,
                      ),
          ),
        ],
      ),
    );
  }

  // ── Table ───────────────────────────────────────────────────────────────
  Widget _tablePanel() {
    final endpoints = _logs.map(_endpoint).toSet().toList()..sort();
    final rows = _pageLogs;
    final f = _filtered;

    return ProPanel(
      title: 'Activity log',
      icon: Icons.table_rows_rounded,
      scroll: false,
      padding: EdgeInsets.zero,
      trailing: Text(
        '${f.length} entries',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
      ),
      child: Column(
        children: [
          // Filter row
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ProChip(
                    label: 'All',
                    selected: _filter == null,
                    count: _logs.length,
                    onTap: () => _setFilter(null),
                  ),
                  for (final e in endpoints) ...[
                    const SizedBox(width: 8),
                    ProChip(
                      label: _label(e),
                      icon: _icon(e),
                      selected: _filter == e,
                      count: _logs.where((l) => _endpoint(l) == e).length,
                      onTap: () => _setFilter(e),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Sticky column header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            color: AppColors.bgSubtle,
            child: const Row(
              children: [
                Expanded(flex: 4, child: _Th('Type')),
                Expanded(flex: 3, child: _Th('Session')),
                Expanded(flex: 2, child: _Th('Time used')),
                Expanded(flex: 3, child: _Th('Date', alignRight: true)),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),

          // Scrollable rows
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text('No entries for this filter',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) => _row(rows[i], i),
                  ),
          ),

          // Pinned pager
          _pager(f.length),
        ],
      ),
    );
  }

  static String _sessionLabel(Map<String, dynamic> m, String endpoint) {
    if (endpoint != 'realtime_token') return '–';
    return m['model_used'] == 'heartbeat' ? 'Streaming' : 'Session start';
  }

  Widget _row(dynamic log, int i) {
    final m = log as Map<String, dynamic>;
    final e = _endpoint(log);
    // The AI model / provider is never shown — only a neutral session label.
    final model = _sessionLabel(m, e);
    final ts = m['timestamp'] as String? ?? '';
    final c = _color(e);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(_icon(e), size: 16, color: c),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _label(e),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              model,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              CreditDisplay.toTime(_credits(log)),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _ts(ts),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pager(int total) {
    final from = total == 0 ? 0 : _page * _pageSize + 1;
    final to = _page * _pageSize + _pageLogs.length;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            'Showing $from–$to of $total',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const Spacer(),
          _PagerBtn(
            icon: Icons.chevron_left_rounded,
            enabled: _page > 0,
            onTap: () => setState(() => _page--),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${_page + 1} / $_totalPages',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          _PagerBtn(
            icon: Icons.chevron_right_rounded,
            enabled: _page < _totalPages - 1,
            onTap: () => setState(() => _page++),
          ),
        ],
      ),
    );
  }

  // ── Summary inspector ───────────────────────────────────────────────────
  Widget _summaryPanel() {
    final all = _logs;
    final totalCredits = all.fold<double>(0, (s, l) => s + _credits(l));
    final byType = <String, double>{};
    final counts = <String, int>{};
    for (final l in all) {
      final e = _endpoint(l);
      byType[e] = (byType[e] ?? 0) + _credits(l);
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final types = byType.keys.toList()
      ..sort((a, b) => byType[b]!.compareTo(byType[a]!));
    final latest = all
        .map((l) => (l as Map<String, dynamic>)['timestamp'] as String? ?? '')
        .fold<String>('', (a, b) => b.compareTo(a) > 0 ? b : a);
    final longest = all.isEmpty
        ? 0.0
        : all.map(_credits).reduce((a, b) => a > b ? a : b);

    return ProPanel(
      title: 'Summary',
      icon: Icons.insights_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProStat(
            label: 'Total time used',
            value: CreditDisplay.toTime(totalCredits),
            hint: '${all.length} sessions',
          ),
          const SizedBox(height: 22),
          const ProLabel('By type'),
          const SizedBox(height: 12),
          for (final e in types) ...[
            _bar(e, byType[e]!, totalCredits, counts[e]!),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 4),
          ProKv('Longest session', CreditDisplay.toTime(longest), mono: true),
          ProKv(
            'Average session',
            CreditDisplay.toTime(all.isEmpty ? 0 : totalCredits / all.length),
            mono: true,
          ),
          ProKv('Last activity', latest.isEmpty ? '–' : _ts(latest),
              mono: true, last: true),
        ],
      ),
    );
  }

  Widget _bar(String e, double v, double total, int n) {
    final pct = total <= 0 ? 0.0 : (v / total).clamp(0.0, 1.0);
    final c = _color(e);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_icon(e), size: 15, color: c),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_label(e),
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 13.5)),
            ),
            Text(
              '${(pct * 100).round()}%',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: AppColors.bgHover,
            valueColor: AlwaysStoppedAnimation(c),
          ),
        ),
      ],
    );
  }
}

// ── Small widgets ────────────────────────────────────────────────────────────

class _Th extends StatelessWidget {
  final String text;
  final bool alignRight;
  const _Th(this.text, {this.alignRight = false});

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _PagerBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PagerBtn(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? AppColors.textSecondary
                : AppColors.textMuted.withValues(alpha: 0.4),
          ),
        ),
      );
}