import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_endpoints.dart';
import 'package:lexilingo_app/features/admin/core/theme/admin_palette.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_theme_toggle.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:lexilingo_app/core/widgets/stagger_list.dart';
import '../../auth/presentation/auth_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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
                'pct': ((e['percentage'] ?? e['pct'] ?? 0) as num) / 100.0,
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
          _error = 'adminUi.dashboard.loadError'.tr();
        });
      }
    }
  }

  double _kpiVal(String key) => ((_kpis?[key] as num?) ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: context.ac.background,
      body: RefreshIndicator(
        color: context.ac.primary,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: context.ac.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0.5,
              leading: MediaQuery.sizeOf(context).width >= adminWideBreakpoint
                  ? null
                  : IconButton(
                      icon: Icon(Icons.menu_rounded, color: context.ac.onSurface),
                      onPressed: AdminShell.openDrawer,
                    ),
              title: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: context.ac.primary,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'L',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: context.ac.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'LexiLingo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.ac.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.ac.primaryContainer,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Text(
                      'ADMIN',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.ac.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                const AdminThemeToggleButton(),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AdminUserAvatar(
                    avatarUrl: user?.avatarUrl,
                    displayName: user?.displayName ?? '',
                    radius: 16,
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              sliver: SliverList(
                delegate: SliverChildListDelegate(_buildBody(context)),
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
        const SizedBox(height: AppSpacing.xl),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 128,
          ),
          itemCount: 4,
          itemBuilder: (_, __) => const StatCardSkeleton(),
        ),
        const SizedBox(height: 14),
        const SectionCardSkeleton(contentHeight: 140),
        const SizedBox(height: AppSpacing.md),
        const SectionCardSkeleton(contentHeight: 88),
      ];
    }

    if (_error != null) {
      return [
        _buildQuickActions(context),
        const SizedBox(height: AppSpacing.lg),
        _ErrorBanner(message: _error!, onRetry: _load),
      ];
    }

    return [
      _buildQuickActions(context),
      const SizedBox(height: AppSpacing.lg),

      // ── KPI Grid ────────────────────────────────────────────────────────
      Text(
        'adminUi.dashboard.keyMetrics'.tr(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: context.ac.onSurfaceMuted,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      if (_kpis == null || _kpis!.isEmpty)
        _EmptyState(message: 'adminUi.dashboard.noKpiData'.tr())
      else ...[
        StaggeredEntrance(
          index: 0,
          child: _PrimaryKpiCard(
            value: _kpiVal('total_users'),
            activeUsers: _kpiVal('active_users_7d'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 132,
          ),
          children: [
            StaggeredEntrance(
              index: 1,
              child: StatCard(
                label: 'adminUi.dashboard.active7d'.tr(),
                value: _kpiVal('active_users_7d').round().toString(),
                icon: Icons.trending_up_rounded,
                note: 'adminUi.dashboard.last7Days'.tr(),
              ),
            ),
            StaggeredEntrance(
              index: 2,
              child: StatCard(
                label: 'adminUi.dashboard.courses'.tr(),
                value: _kpiVal('total_courses').round().toString(),
                icon: Icons.menu_book_rounded,
                note: 'adminUi.dashboard.published'.tr(),
              ),
            ),
            StaggeredEntrance(
              index: 3,
              child: StatCard(
                label: 'adminUi.dashboard.avgDau'.tr(),
                value: _kpiVal('avg_dau_30d').round().toString(),
                icon: Icons.bar_chart_rounded,
                note: 'adminUi.dashboard.avg30Days'.tr(),
              ),
            ),
            StaggeredEntrance(
              index: 4,
              child: StatCard(
                label: 'adminUi.dashboard.lessonsToday'.tr(),
                value: _kpiVal(
                  'total_lessons_completed_today',
                ).round().toString(),
                icon: Icons.task_alt_rounded,
                note: 'adminUi.dashboard.completed'.tr(),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: AppSpacing.md),

      // ── DAU Line Chart ───────────────────────────────────────────────────
      StaggeredEntrance(
        index: 5,
        child: _SectionCard(
          title: 'adminUi.dashboard.dailyActiveUsers'.tr(),
          subtitle: 'adminUi.dashboard.engagementOver10Weeks'.tr(),
          trailing: _Chip(label: 'adminUi.dashboard.10Weeks'.tr()),
          child: _dauSeries.isEmpty
              ? _EmptyState(
                  message: 'adminUi.dashboard.noEngagementData'.tr(),
                )
              : SizedBox(
                  height: 144,
                  child: _DauLineChart(
                    values: _dauSeries,
                    labelPrefix: 'adminUi.dashboard.weekPrefix'.tr(),
                  ),
                ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // ── User Growth ──────────────────────────────────────────────────────
      StaggeredEntrance(
        index: 6,
        child: _SectionCard(
          title: 'adminUi.dashboard.userGrowth'.tr(),
          subtitle: 'adminUi.dashboard.totalRegisteredUsersOver30'.tr(),
          trailing: _Chip(label: 'adminUi.dashboard.30Days'.tr()),
          child: _growthSeries.isEmpty
              ? _EmptyState(
                  message: 'adminUi.dashboard.noGrowthData'.tr(),
                )
              : SizedBox(
                  height: 144,
                  child: _DauLineChart(
                    values: _growthSeries,
                    labelPrefix: 'adminUi.dashboard.dayPrefix'.tr(),
                  ),
                ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // ── Language Distribution ────────────────────────────────────────────
      StaggeredEntrance(
        index: 7,
        child: _SectionCard(
          title: 'adminUi.dashboard.languages'.tr(),
          subtitle: 'adminUi.dashboard.enrollmentDistribution'.tr(),
          child: _languages.isEmpty
              ? _EmptyState(message: 'adminUi.dashboard.noLanguageData'.tr())
              : Column(
                  children: _languages.asMap().entries.map((entry) {
                    final i = entry.key;
                    final l = entry.value;
                    return Column(
                      children: [
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
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
          'adminUi.dashboard.quickActions'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.ac.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _QuickAction(
                icon: Icons.add_circle_outline,
                label: 'adminUi.dashboard.newLesson'.tr(),
                filled: true,
                onTap: () => context.push('/curriculum'),
              ),
              const SizedBox(width: AppSpacing.sm),
              _QuickAction(
                icon: Icons.group_outlined,
                label: 'adminUi.dashboard.users'.tr(),
                filled: false,
                onTap: () => context.push('/users'),
              ),
              const SizedBox(width: AppSpacing.sm),
              _QuickAction(
                icon: Icons.bar_chart_outlined,
                label: 'adminUi.dashboard.analytics'.tr(),
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
        color: context.ac.primary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'adminUi.dashboard.totalUsers'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.ac.surface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _format(value),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.ac.surface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'adminUi.dashboard.nActiveInTheLast'.tr(
                    args: [_format(activeUsers)],
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.ac.surface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.group_outlined, color: context.ac.surface, size: 32),
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
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.ac.onSurfaceMuted),
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

    final rawMin = values.fold(values.first, (a, b) => a < b ? a : b);
    final rawMax = values.fold(values.first, (a, b) => a > b ? a : b);
    final minY = rawMin <= 0 ? 0.0 : (rawMin * 0.9).floorToDouble();
    final span = (rawMax - minY).clamp(4.0, double.infinity);
    final yInterval = (span / 4).ceilToDouble().clamp(1.0, double.infinity);
    final maxY = minY + yInterval * 4;
    final xStep = (values.length / 5).ceil().clamp(1, values.length);

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: context.ac.outline, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: yInterval,
              getTitlesWidget: (value, _) {
                if (value < minY || value > maxY) {
                  return const SizedBox.shrink();
                }
                if (((value - minY) % yInterval).abs() > 0.01) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    _formatY(value),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.ac.onSurfaceMuted,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) {
                final i = value.round();
                if ((value - i).abs() > 0.01 || i < 0 || i >= values.length) {
                  return const SizedBox.shrink();
                }
                final isLast = i == values.length - 1;
                final isStep = i % xStep == 0;
                final tooCloseToLast =
                    !isLast && (values.length - 1 - i) < (xStep / 2).ceil();
                if ((!isStep && !isLast) || tooCloseToLast) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$labelPrefix${i + 1}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.ac.onSurfaceMuted,
                      fontSize: 10,
                    ),
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
            color: context.ac.primaryBright,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: context.ac.surface,
                strokeWidth: 2,
                strokeColor: context.ac.primaryBright,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  context.ac.primaryBright.withValues(alpha: 0.2),
                  context.ac.primaryBright.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => context.ac.navy,
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                _formatY(s.y),
                Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: context.ac.onNavy,
                  fontWeight: FontWeight.w700,
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
              ? context.ac.primaryBright
              : context.ac.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: filled ? null : Border.all(color: context.ac.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: filled ? context.ac.surface : context.ac.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: filled ? context.ac.surface : context.ac.primary,
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
        color: context.ac.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.ac.outlineVariant, width: 0.5),
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.ac.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.ac.onSurfaceMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
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
        color: context.ac.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: context.ac.onSurfaceVariant,
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.ac.onSurface),
            ),
            Text(
              'adminUi.dashboard.n'.tr(
                args: [((pct * 100).toInt()).toString()],
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.ac.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: context.ac.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation(context.ac.primary),
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
        color: context.ac.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.ac.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: context.ac.error, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.ac.error),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: context.ac.error,
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              'adminUi.dashboard.retry'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
