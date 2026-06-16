import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../../../shared/widgets/staggered_entrance.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final resp = await ApiClient.instance
          .get('/admin/analytics/dashboard/kpis');
      if (mounted) {
        setState(() {
          _data = resp['kpis'] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(dynamic n) {
    final num v = n is num ? n : (double.tryParse(n.toString()) ?? 0);
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(v == v.truncate() ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            floating: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
              onPressed: AdminShell.openDrawer,
            ),
            title: Text(
              'Analytics',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.calendar_today_outlined, size: 14),
                label: Text(
                  'Last 30 Days',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download_outlined, size: 14),
                label: Text(
                  'Export',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            bottom: TabBar(
              controller: _tabs,
              labelStyle: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              unselectedLabelStyle: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              labelColor: AppColors.primaryBright,
              unselectedLabelColor: AppColors.onSurfaceMuted,
              indicatorColor: AppColors.primaryBright,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Engagement'),
                Tab(text: 'Leaderboard'),
              ],
            ),
          ),
        ],
        body: _loading
            ? _buildSkeleton()
            : TabBarView(
                controller: _tabs,
                children: [
                  _OverviewTab(data: _data, fmt: _fmt),
                  _EngagementTab(),
                  _LeaderboardTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: List.generate(4, (_) => const StatCardSkeleton()),
          ),
          const SizedBox(height: 16),
          const SectionCardSkeleton(contentHeight: 180),
          const SizedBox(height: 16),
          const SectionCardSkeleton(contentHeight: 120),
        ],
      ),
    );
  }
}

// ── Overview Tab ─────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic>? data;
  final String Function(dynamic) fmt;

  const _OverviewTab({required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // KPI row
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              StaggeredEntrance(
                index: 0,
                child: _AnalyticStat(
                  label: 'TOTAL USERS',
                  value: fmt(data?['total_users'] ?? 109),
                  change: 'All time',
                  icon: Icons.group_outlined,
                ),
              ),
              StaggeredEntrance(
                index: 1,
                child: _AnalyticStat(
                  label: 'ACTIVE 7D',
                  value: fmt(data?['active_users_7d'] ?? 0),
                  change: 'Last 7 days',
                  icon: Icons.timer_outlined,
                ),
              ),
              StaggeredEntrance(
                index: 2,
                child: _AnalyticStat(
                  label: 'COURSES',
                  value: fmt(data?['total_courses'] ?? 11),
                  changePositive: true,
                  change: 'Live',
                  icon: Icons.check_circle_outline,
                ),
              ),
              StaggeredEntrance(
                index: 3,
                child: _AnalyticStat(
                  label: 'QUESTIONS',
                  value: fmt(data?['total_questions'] ?? 98),
                  change: 'Question bank',
                  changePositive: true,
                  icon: Icons.quiz_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // DAU sparkline
          StaggeredEntrance(
            index: 4,
            child: _CardContainer(
              title: 'Daily Active Users',
              subtitle: 'User engagement — last 14 days',
              child: SizedBox(
                height: 120,
                child: _SparkLine(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Language popularity
          StaggeredEntrance(
            index: 5,
            child: _CardContainer(
              title: 'Popular Languages',
              subtitle: 'Course enrollment by volume',
              child: Column(
                children: [
                  _LangProgress(lang: 'English (EN)', pct: 0.42),
                  const SizedBox(height: 10),
                  _LangProgress(lang: 'French (FR)', pct: 0.28),
                  const SizedBox(height: 10),
                  _LangProgress(lang: 'Japanese (JA)', pct: 0.18),
                  const SizedBox(height: 10),
                  _LangProgress(lang: 'German (DE)', pct: 0.12),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // AI insight dark card
          StaggeredEntrance(
            index: 6,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBright,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.psychology_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'AI Content Insight',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ML recommendations based on drop-off analysis',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '"Increasing gamified quiz density in Level 2 French could boost retention by an estimated 14% based on current user flow drop-offs."',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBright,
                    ),
                    child: Text(
                      'Apply Suggested Optimizations',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
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

// ── Engagement Tab (heatmap + funnel) ────────────────────────────────────────

class _EngagementTab extends StatelessWidget {
  const _EngagementTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Activity heatmap
          StaggeredEntrance(
            index: 0,
            child: _CardContainer(
              title: 'Activity Heatmap',
              subtitle: 'Sessions by day of week and hour',
              child: const _ActivityHeatmap(),
            ),
          ),
          const SizedBox(height: 16),

          // Conversion funnel
          StaggeredEntrance(
            index: 1,
            child: _CardContainer(
              title: 'Conversion Funnel',
              subtitle: 'Registration through subscription',
              child: const _FunnelChart(),
            ),
          ),
          const SizedBox(height: 16),

          // Retention cohort summary
          StaggeredEntrance(
            index: 2,
            child: _CardContainer(
              title: 'Retention Summary',
              subtitle: 'Day 1 / Day 7 / Day 30 retention',
              child: Row(
                children: [
                  _RetentionCell(label: 'Day 1', value: 72),
                  const SizedBox(width: 12),
                  _RetentionCell(label: 'Day 7', value: 41),
                  const SizedBox(width: 12),
                  _RetentionCell(label: 'Day 30', value: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Leaderboard Tab ──────────────────────────────────────────────────────────

class _LeaderboardTab extends StatelessWidget {
  const _LeaderboardTab();

  static const _entries = [
    {'name': 'Nguyen Lan', 'xp': 24800, 'level': 'A2', 'streak': 45},
    {'name': 'Tran Minh', 'xp': 22100, 'level': 'B1', 'streak': 32},
    {'name': 'Le Phuong', 'xp': 19600, 'level': 'A2', 'streak': 28},
    {'name': 'Hoang Nam', 'xp': 17300, 'level': 'A1', 'streak': 21},
    {'name': 'Vo Thi Hoa', 'xp': 15900, 'level': 'B2', 'streak': 19},
    {'name': 'Dang Van An', 'xp': 14200, 'level': 'A1', 'streak': 14},
    {'name': 'Bui Thanh', 'xp': 12800, 'level': 'A2', 'streak': 12},
    {'name': 'Pham Quynh', 'xp': 11500, 'level': 'B1', 'streak': 9},
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaggeredEntrance(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, AppColors.navyLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 36),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Leaderboard',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${_entries.length} active competitors this week',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant, width: 0.5),
            ),
            child: Column(
              children: _entries.asMap().entries.map((entry) {
                final i = entry.key;
                final user = entry.value;
                return StaggeredEntrance(
                  index: i + 1,
                  child: _LeaderboardRow(
                    rank: i + 1,
                    name: user['name'] as String,
                    xp: user['xp'] as int,
                    level: user['level'] as String,
                    streak: user['streak'] as int,
                    showDivider: i < _entries.length - 1,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ActivityHeatmap extends StatelessWidget {
  const _ActivityHeatmap();

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _hours = [0, 4, 8, 12, 16, 20];

  // Simulated activity grid: [day][hourBucket]
  static final _grid = List.generate(7, (d) {
    return List.generate(6, (h) {
      // Simulate: more activity on evenings (h=4,5) and weekends (d=5,6)
      final base = math.Random(d * 6 + h).nextDouble();
      final eveningBoost = (h >= 4) ? 0.4 : 0.0;
      final weekendBoost = (d >= 5) ? 0.2 : 0.0;
      return (base + eveningBoost + weekendBoost).clamp(0.0, 1.0);
    });
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hour labels
        Padding(
          padding: const EdgeInsets.only(left: 36),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _hours
                .map(
                  (h) => Text(
                    '${h.toString().padLeft(2, '0')}h',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        // Grid rows
        ...List.generate(_days.length, (d) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    _days[d],
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ...List.generate(_hours.length, (h) {
                  final intensity = _grid[d][h];
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              AppColors.surfaceContainerLow,
                              AppColors.primaryBright,
                              intensity,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Less',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: AppColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(width: 4),
            ...List.generate(5, (i) {
              return Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    AppColors.surfaceContainerLow,
                    AppColors.primaryBright,
                    i / 4.0,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
            const SizedBox(width: 4),
            Text(
              'More',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FunnelChart extends StatelessWidget {
  const _FunnelChart();

  static const _steps = [
    {'label': 'Registration', 'value': 109, 'pct': 1.0},
    {'label': 'First Lesson', 'value': 87, 'pct': 0.80},
    {'label': 'Course Completion', 'value': 52, 'pct': 0.48},
    {'label': 'Subscription', 'value': 23, 'pct': 0.21},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _steps.asMap().entries.map((entry) {
        final i = entry.key;
        final step = entry.value;
        final isLast = i == _steps.length - 1;
        final pct = step['pct'] as double;

        final barColor = Color.lerp(
          AppColors.primaryBright,
          AppColors.primary,
          i / (_steps.length - 1).toDouble(),
        )!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: barColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step['label'] as String,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                Text(
                  '${step['value']}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(pct * 100).toInt()}%',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: AppColors.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(barColor),
                minHeight: 6,
              ),
            ),
            if (!isLast) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Row(
                  children: [
                    Container(
                      width: 2,
                      height: 12,
                      color: AppColors.outline,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        );
      }).toList(),
    );
  }
}

class _RetentionCell extends StatelessWidget {
  final String label;
  final int value;

  const _RetentionCell({required this.label, required this.value});

  Color get _color {
    if (value >= 60) return AppColors.success;
    if (value >= 30) return AppColors.warning;
    return AppColors.error;
  }

  Color get _bgColor {
    if (value >= 60) return AppColors.successContainer;
    if (value >= 30) return AppColors.warningContainer;
    return AppColors.errorContainer;
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$value%',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final String name;
  final int xp;
  final String level;
  final int streak;
  final bool showDivider;

  const _LeaderboardRow({
    required this.rank,
    required this.name,
    required this.xp,
    required this.level,
    required this.streak,
    this.showDivider = true,
  });

  Color get _rankColor {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFC0C0C0);
    if (rank == 3) return const Color(0xFFCD7F32);
    return AppColors.onSurfaceMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '#$rank',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _rankColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryContainer,
                child: Text(
                  name[0].toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            level,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.local_fire_department,
                          size: 12,
                          color: AppColors.warning,
                        ),
                        Text(
                          '$streak',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            color: AppColors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(xp / 1000).toStringAsFixed(1)}K',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    'XP',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _AnalyticStat extends StatelessWidget {
  final String label;
  final String value;
  final String change;
  final bool changePositive;
  final IconData icon;

  const _AnalyticStat({
    required this.label,
    required this.value,
    required this.change,
    this.changePositive = true,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 16),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: changePositive
                      ? AppColors.successContainer
                      : AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  change,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: changePositive
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
              color: AppColors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              letterSpacing: -0.03,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkLine extends StatelessWidget {
  final List<double> _points = const [
    0.30, 0.50, 0.40, 0.70, 0.60, 0.80, 0.75, 0.65, 0.70, 0.90, 0.85, 0.80, 0.75, 0.90,
  ];

  @override
  Widget build(BuildContext context) {
    final spots = _points.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: 6,
              getTitlesWidget: (value, _) {
                const labels = ['01 May', '07 May', '14 May'];
                final i = (value / 6).round();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Text(
                  labels[i],
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: AppColors.onSurfaceMuted,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.15),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LangProgress extends StatelessWidget {
  final String lang;
  final double pct;
  const _LangProgress({required this.lang, required this.pct});

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

class _CardContainer extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _CardContainer({
    required this.title,
    required this.subtitle,
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
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              color: AppColors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
