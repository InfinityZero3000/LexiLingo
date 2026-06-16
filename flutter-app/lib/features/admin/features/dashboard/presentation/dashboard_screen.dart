import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../../../shared/widgets/kpi_count_card.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../auth/presentation/auth_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _kpis;
  List<double> _dauSeries = [];
  List<Map<String, dynamic>> _languages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/admin/analytics/dashboard/kpis'),
        ApiClient.instance.get(
          '/admin/analytics/dashboard/engagement',
          params: {'weeks': 10},
        ),
      ]);
      final kpisRaw = results[0];
      final engagementRaw = results[1];

      final List<dynamic> weekData = (engagementRaw['data'] as List?) ?? [];
      final dau = weekData
          .map<double>((e) => ((e['dau'] as num?) ?? 0).toDouble())
          .toList();

      final kpisMap = kpisRaw['kpis'] as Map<String, dynamic>?;
      List<Map<String, dynamic>> langs = [];
      final rawLangs = kpisMap?['language_distribution'] as List?;
      if (rawLangs != null && rawLangs.isNotEmpty) {
        langs = rawLangs
            .take(3)
            .map<Map<String, dynamic>>(
              (e) => {
                'lang': (e['language'] ?? e['lang'] ?? '').toString(),
                'pct':
                    ((e['percentage'] ?? e['pct'] ?? 0) as num) / 100.0,
              },
            )
            .toList();
      }

      if (mounted) {
        setState(() {
          _kpis = kpisMap;
          _dauSeries = dau;
          _languages = langs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load data. Pull to refresh.';
        });
      }
    }
  }

  double _kpiVal(String key) =>
      ((_kpis?[key] as num?) ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.menu_rounded,
                  color: AppColors.onSurface,
                ),
                onPressed: AdminShell.openDrawer,
              ),
              title: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.language,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'LingoAdmin',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: AppColors.onSurface,
                  ),
                  onPressed: () {},
                ),
                if (user?.avatarUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundImage: NetworkImage(user!.avatarUrl!),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primaryContainer,
                      child: Text(
                        (user?.displayName.isNotEmpty == true)
                            ? user!.displayName[0].toUpperCase()
                            : 'A',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _buildBody(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    if (_loading) {
      return [
        _buildQuickActions(context),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: List.generate(4, (_) => const StatCardSkeleton()),
        ),
        const SizedBox(height: 20),
        const SectionCardSkeleton(contentHeight: 160),
        const SizedBox(height: 16),
        const SectionCardSkeleton(contentHeight: 100),
      ];
    }

    return [
      if (_error != null) ...[
        _ErrorBanner(message: _error!, onRetry: _load),
        const SizedBox(height: 12),
      ],
      _buildQuickActions(context),
      const SizedBox(height: 24),

      // ── KPI Grid ────────────────────────────────────────────────────────
      Text(
        'KEY METRICS',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08,
          color: AppColors.onSurfaceMuted,
        ),
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
        children: [
          StaggeredEntrance(
            index: 0,
            child: KpiCountCard(
              label: 'Total Users',
              value: _kpiVal('total_users'),
              icon: Icons.group_outlined,
              change: 'All time',
            ),
          ),
          StaggeredEntrance(
            index: 1,
            child: KpiCountCard(
              label: 'Active 7d',
              value: _kpiVal('active_users_7d'),
              icon: Icons.trending_up_outlined,
              change: '+12%',
              changePositive: true,
            ),
          ),
          StaggeredEntrance(
            index: 2,
            child: KpiCountCard(
              label: 'Courses',
              value: _kpiVal('total_courses'),
              icon: Icons.menu_book_outlined,
              change: 'Published',
              changePositive: true,
            ),
          ),
          StaggeredEntrance(
            index: 3,
            child: KpiCountCard(
              label: 'Avg DAU',
              value: _kpiVal('avg_dau_30d'),
              icon: Icons.bar_chart_outlined,
              change: '30-day avg',
              changePositive: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),

      // ── DAU Line Chart ───────────────────────────────────────────────────
      StaggeredEntrance(
        index: 4,
        child: _SectionCard(
          title: 'Daily Active Users',
          subtitle: 'Engagement over 10 weeks',
          trailing: _Chip(label: '10 Weeks'),
          child: SizedBox(
            height: 160,
            child: _DauLineChart(
              values: _dauSeries.isNotEmpty
                  ? _dauSeries
                  : [40, 55, 48, 70, 62, 80, 72, 55, 65, 90],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),

      // ── Recent Activity Feed ─────────────────────────────────────────────
      StaggeredEntrance(
        index: 5,
        child: _SectionCard(
          title: 'Recent Activity',
          subtitle: 'Latest platform events',
          child: Column(
            children: _mockActivity
                .map(
                  (a) => _ActivityRow(
                    icon: a['icon'] as IconData,
                    color: a['color'] as Color,
                    title: a['title'] as String,
                    subtitle: a['subtitle'] as String,
                    time: a['time'] as String,
                  ),
                )
                .toList(),
          ),
        ),
      ),
      const SizedBox(height: 16),

      // ── Language Distribution ────────────────────────────────────────────
      StaggeredEntrance(
        index: 6,
        child: _SectionCard(
          title: 'Languages',
          subtitle: 'Enrollment distribution',
          child: Column(
            children: _languages.isNotEmpty
                ? _languages.asMap().entries.map((entry) {
                    final i = entry.key;
                    final l = entry.value;
                    return Column(
                      children: [
                        if (i > 0) const SizedBox(height: 10),
                        _LanguageBar(
                          lang: l['lang'] as String,
                          pct: (l['pct'] as double).clamp(0.0, 1.0),
                        ),
                      ],
                    );
                  }).toList()
                : [
                    _LanguageBar(lang: 'English', pct: 0.42),
                    const SizedBox(height: 10),
                    _LanguageBar(lang: 'French', pct: 0.28),
                    const SizedBox(height: 10),
                    _LanguageBar(lang: 'Japanese', pct: 0.15),
                  ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // ── Quick Actions ── (secondary row) ───────────────────────────────
      StaggeredEntrance(
        index: 7,
        child: _SectionCard(
          title: 'System Alerts',
          child: Column(
            children: [
              _AlertRow(
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                title: 'All services healthy',
                subtitle: 'Backend + AI service responding normally.',
              ),
              const Divider(height: 16),
              _AlertRow(
                icon: Icons.warning_amber_outlined,
                color: AppColors.warning,
                title: 'STT queue backlog',
                subtitle: 'Phase 3 ensemble latency +18% above baseline.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // ── Growth Target card (dark) ───────────────────────────────────────
      StaggeredEntrance(
        index: 8,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Growth Target',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '85% of quarterly acquisition goal reached.',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PROGRESS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      letterSpacing: 0.08,
                      fontWeight: FontWeight.w700,
                      color: Colors.white38,
                    ),
                  ),
                  Text(
                    '850K / 1M',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 0.85,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(
                    AppColors.primaryBright,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white38),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => context.push('/analytics'),
                    child: const Text('View Analytics'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white38),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {},
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Export CSV'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _QuickAction(
                icon: Icons.add_circle_outline,
                label: 'NEW LESSON',
                filled: true,
                onTap: () => context.push('/curriculum'),
              ),
              const SizedBox(width: 8),
              _QuickAction(
                icon: Icons.group_outlined,
                label: 'USERS',
                filled: false,
                onTap: () => context.push('/users'),
              ),
              const SizedBox(width: 8),
              _QuickAction(
                icon: Icons.bar_chart_outlined,
                label: 'ANALYTICS',
                filled: false,
                onTap: () => context.push('/analytics'),
              ),
              const SizedBox(width: 8),
              _QuickAction(
                icon: Icons.campaign_outlined,
                label: 'BROADCAST',
                filled: false,
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Mock data ────────────────────────────────────────────────────────────────

const _mockActivity = [
  {
    'icon': Icons.person_add_outlined,
    'color': AppColors.success,
    'title': 'New registration',
    'subtitle': 'nguyen.lan@example.com joined',
    'time': '2m ago',
  },
  {
    'icon': Icons.menu_book_outlined,
    'color': AppColors.primary,
    'title': 'Course completed',
    'subtitle': 'English Beginners — user #LX-4821',
    'time': '14m ago',
  },
  {
    'icon': Icons.star_outlined,
    'color': AppColors.warning,
    'title': 'Achievement unlocked',
    'subtitle': 'Streak Master — 30 day streak',
    'time': '1h ago',
  },
  {
    'icon': Icons.flag_outlined,
    'color': AppColors.error,
    'title': 'Content flagged',
    'subtitle': 'Grammar rule #47 reported by 3 users',
    'time': '3h ago',
  },
];

// ── Widgets ──────────────────────────────────────────────────────────────────

class _DauLineChart extends StatelessWidget {
  final List<double> values;
  const _DauLineChart({required this.values});

  @override
  Widget build(BuildContext context) {
    final spots = values.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    final max = values.fold(0.0, (a, b) => a > b ? a : b);
    final min = values.fold(max, (a, b) => a < b ? a : b);
    final padding = (max - min) * 0.15;

    return LineChart(
      LineChartData(
        minY: (min - padding).clamp(0, double.infinity),
        maxY: max + padding,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (max / 4).clamp(1, double.infinity),
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppColors.outline,
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: (max / 4).clamp(1, double.infinity),
              getTitlesWidget: (value, _) => Text(
                _formatY(value),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (values.length / 5).ceilToDouble().clamp(1, double.infinity),
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= values.length) return const SizedBox.shrink();
                return Text(
                  'W${i + 1}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: AppColors.onSurfaceMuted,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.primaryBright,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: AppColors.primaryBright,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primaryBright.withValues(alpha: 0.2),
                  AppColors.primaryBright.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.navy,
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                _formatY(s.y),
                GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _formatY(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toInt().toString();
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryBright : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: filled
              ? null
              : Border.all(color: AppColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: filled ? Colors.white : AppColors.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.05,
                color: filled ? Colors.white : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LanguageBar extends StatelessWidget {
  final String lang;
  final double pct;
  const _LanguageBar({required this.lang, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              lang,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              '${(pct * 100).toInt()}%',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppColors.surfaceContainerHigh,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;

  const _ActivityRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _AlertRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
