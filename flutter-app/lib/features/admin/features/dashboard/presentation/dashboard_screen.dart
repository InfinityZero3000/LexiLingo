import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_endpoints.dart';
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
  List<double> _growthSeries = [];
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
        ApiClient.instance.get(ApiEndpoints.analyticsKpis),
        ApiClient.instance.get(
          ApiEndpoints.analyticsEngagement,
          params: {'weeks': 10},
        ),
        ApiClient.instance.get(
          ApiEndpoints.analyticsUserGrowth,
          params: {'days': 30},
        ),
      ]);
      final kpisRaw = results[0];
      final engagementRaw = results[1];
      final growthRaw = results[2];

      final List<dynamic> weekData = (engagementRaw['data'] as List?) ?? [];
      final dau = weekData
          .map<double>((e) => ((e['dau'] as num?) ?? 0).toDouble())
          .toList();
      final List<dynamic> growthData = (growthRaw['data'] as List?) ?? [];
      final growth = growthData
          .map<double>((e) => ((e['total_users'] as num?) ?? 0).toDouble())
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
          _growthSeries = growth;
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
                      color: AppColors.surface,
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
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryContainer,
                    // Initial is always the child so it still shows if the
                    // network avatar below fails to load — onBackgroundImageError
                    // only silences the exception, it can't swap in a fallback.
                    backgroundImage:
                        user?.avatarUrl?.trim().isNotEmpty == true
                        ? NetworkImage(user!.avatarUrl!.trim())
                        : null,
                    onBackgroundImageError:
                        user?.avatarUrl?.trim().isNotEmpty == true
                        ? (_, __) {}
                        : null,
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
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
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: List.generate(4, (_) => const StatCardSkeleton()),
        ),
        const SizedBox(height: 14),
        const SectionCardSkeleton(contentHeight: 140),
        const SizedBox(height: 12),
        const SectionCardSkeleton(contentHeight: 88),
      ];
    }

    if (_error != null) {
      return [
        _buildQuickActions(context),
        const SizedBox(height: 16),
        _ErrorBanner(message: _error!, onRetry: _load),
      ];
    }

    return [
      _buildQuickActions(context),
      const SizedBox(height: 16),

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
      const SizedBox(height: 8),
      if (_kpis == null || _kpis!.isEmpty)
        const _EmptyState(message: 'No KPI data is available yet.')
      else ...[
        StaggeredEntrance(
          index: 0,
          child: _PrimaryKpiCard(
            value: _kpiVal('total_users'),
            activeUsers: _kpiVal('active_users_7d'),
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            StaggeredEntrance(
              index: 1,
              child: KpiCountCard(
                label: 'Active 7d',
                value: _kpiVal('active_users_7d'),
                icon: Icons.trending_up_outlined,
                change: 'Last 7 days',
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
            StaggeredEntrance(
              index: 4,
              child: KpiCountCard(
                label: 'Lessons Today',
                value: _kpiVal('total_lessons_completed_today'),
                icon: Icons.task_alt_outlined,
                change: 'Completed',
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),

      // ── DAU Line Chart ───────────────────────────────────────────────────
      StaggeredEntrance(
        index: 5,
        child: _SectionCard(
          title: 'Daily Active Users',
          subtitle: 'Engagement over 10 weeks',
          trailing: _Chip(label: '10 Weeks'),
          child: _dauSeries.isEmpty
              ? const _EmptyState(message: 'No engagement data for this period.')
              : SizedBox(
                  height: 130,
                  child: _DauLineChart(values: _dauSeries),
                ),
        ),
      ),
      const SizedBox(height: 12),

      // ── User Growth ──────────────────────────────────────────────────────
      StaggeredEntrance(
        index: 6,
        child: _SectionCard(
          title: 'User Growth',
          subtitle: 'Total registered users over 30 days',
          trailing: const _Chip(label: '30 Days'),
          child: _growthSeries.isEmpty
              ? const _EmptyState(message: 'No user growth data for this period.')
              : SizedBox(
                  height: 130,
                  child: _DauLineChart(values: _growthSeries, labelPrefix: 'D'),
                ),
        ),
      ),
      const SizedBox(height: 12),

      // ── Language Distribution ────────────────────────────────────────────
      StaggeredEntrance(
        index: 7,
        child: _SectionCard(
          title: 'Languages',
          subtitle: 'Enrollment distribution',
          child: _languages.isEmpty
              ? const _EmptyState(message: 'No language enrollment data yet.')
              : Column(
                  children: _languages.asMap().entries.map((entry) {
                    final i = entry.key;
                    final l = entry.value;
                    return Column(
                      children: [
                        if (i > 0) const SizedBox(height: 8),
                        _LanguageBar(
                          lang: l['lang'] as String,
                          pct: (l['pct'] as double).clamp(0.0, 1.0),
                        ),
                      ],
                    );
                  }).toList(),
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
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
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
            ],
          ),
        ),
      ],
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _PrimaryKpiCard extends StatelessWidget {
  final double value;
  final double activeUsers;

  const _PrimaryKpiCard({required this.value, required this.activeUsers});

  String _format(double number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL USERS',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.surface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _format(value),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.surface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_format(activeUsers)} active in the last 7 days',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    color: AppColors.surface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.group_outlined, color: AppColors.surface, size: 32),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            color: AppColors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}

class _DauLineChart extends StatelessWidget {
  final List<double> values;
  final String labelPrefix;
  const _DauLineChart({required this.values, this.labelPrefix = 'W'});

  @override
  Widget build(BuildContext context) {
    final spots = values.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    final max = values
        .fold(0.0, (a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity)
        .toDouble();
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
                  '$labelPrefix${i + 1}',
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
                color: AppColors.surface,
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
                  color: AppColors.surface,
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
          color: filled
              ? AppColors.primaryBright
              : AppColors.surface.withValues(alpha: 0),
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
              color: filled ? AppColors.surface : AppColors.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.05,
                color: filled ? AppColors.surface : AppColors.primary,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
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
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
