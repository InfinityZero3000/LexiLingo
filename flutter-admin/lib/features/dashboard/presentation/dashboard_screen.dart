import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../auth/presentation/auth_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _kpis;
  List<double> _dauSeries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/admin/analytics/dashboard/kpis'),
        ApiClient.instance.get('/admin/analytics/dashboard/engagement', params: {'weeks': 10}),
      ]);
      // KPIs response: {"kpis": {...}} — no ApiResponse wrapper
      final kpisRaw = results[0];
      // Engagement response: {"data": [...]} — no ApiResponse wrapper
      final engagementRaw = results[1];

      final List<dynamic> weekData =
          (engagementRaw['data'] as List?) ?? [];
      final dau = weekData
          .map<double>((e) => ((e['dau'] as num?) ?? 0).toDouble())
          .toList();

      if (mounted) {
        setState(() {
          _kpis = kpisRaw['kpis'] as Map<String, dynamic>?;
          _dauSeries = dau;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

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
                icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
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
                    child: const Icon(Icons.language, color: Colors.white, size: 18),
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
                  icon: const Icon(Icons.notifications_outlined, color: AppColors.onSurface),
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
                delegate: SliverChildListDelegate([
                  // Quick Actions
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
                          icon: Icons.person_add_outlined,
                          label: 'INVITE ADMIN',
                          filled: false,
                          onTap: () {},
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
                  const SizedBox(height: 24),
                  // Stats grid
                  if (_loading)
                    const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  else ...[
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.1,
                      children: [
                        StatCard(
                          label: 'Total Users',
                          value: _formatNum(_kpis?['total_users'] ?? 0),
                          icon: Icons.group_outlined,
                          change: 'All time',
                        ),
                        StatCard(
                          label: 'Active 7d',
                          value: _formatNum(_kpis?['active_users_7d'] ?? 0),
                          icon: Icons.trending_up_outlined,
                          change: 'Last 7 days',
                          changePositive: true,
                        ),
                        StatCard(
                          label: 'Courses',
                          value: _formatNum(_kpis?['total_courses'] ?? 0),
                          icon: Icons.menu_book_outlined,
                          change: 'Published',
                          changePositive: true,
                        ),
                        StatCard(
                          label: 'Avg DAU',
                          value: _formatNum(_kpis?['avg_dau_30d'] ?? 0),
                          icon: Icons.bar_chart_outlined,
                          change: '30-day avg',
                          changePositive: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Engagement overview card
                    _SectionCard(
                      title: 'Engagement Overview',
                      subtitle: 'Daily active users (10 weeks)',
                      trailing: _Chip(label: '10 Weeks'),
                      child: SizedBox(
                        height: 120,
                        child: _BarChart(
                          values: _dauSeries.isNotEmpty
                              ? _dauSeries
                              : [40, 55, 48, 70, 62, 80, 72, 55, 65, 90],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Languages
                    _SectionCard(
                      title: 'Languages',
                      child: Column(
                        children: [
                          _LanguageBar(lang: 'English', pct: 0.42),
                          const SizedBox(height: 10),
                          _LanguageBar(lang: 'French', pct: 0.28),
                          const SizedBox(height: 10),
                          _LanguageBar(lang: 'Japanese', pct: 0.15),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Recent Alerts
                    _SectionCard(
                      title: 'Recent Alerts',
                      child: Column(
                        children: [
                          _AlertRow(
                            icon: Icons.warning_amber_outlined,
                            color: AppColors.warning,
                            title: 'Server Spike - EU',
                            subtitle: 'Traffic +300% in last 15 min.',
                          ),
                          const Divider(height: 16),
                          _AlertRow(
                            icon: Icons.check_circle_outline,
                            color: AppColors.success,
                            title: 'New Course Published',
                            subtitle: 'Advanced Portuguese live.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Growth Target dark card
                    Container(
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
                              valueColor: const AlwaysStoppedAnimation(AppColors.primaryBright),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white38),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => context.push('/settings/analytics'),
                            child: const Text('Strategy'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNum(dynamic n) {
    final num v = n is num ? n : 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryBright : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: AppColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: filled ? Colors.white : AppColors.primary, size: 16),
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
              Column(
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

class _BarChart extends StatelessWidget {
  final List<double> values;
  const _BarChart({required this.values});

  @override
  Widget build(BuildContext context) {
    final max = values.fold(0.0, (a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: values.map((v) {
        final ratio = max > 0 ? v / max : 0.0;
        final isMax = v == max;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FractionallySizedBox(
              alignment: Alignment.bottomCenter,
              heightFactor: ratio.clamp(0.1, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: isMax ? AppColors.primary : AppColors.primaryContainer,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
            Text(lang, style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurface)),
            Text('${(pct * 100).toInt()}%',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface)),
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
                style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
