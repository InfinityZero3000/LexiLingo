import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/admin_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:lexilingo_app/core/widgets/stagger_list.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.get(ApiEndpoints.analyticsKpis);
      final value = response['kpis'] ?? response['data'];
      if (mounted) {
        setState(
          () => _data = value is Map ? Map<String, dynamic>.from(value) : null,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load analytics.\n$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _format(dynamic value) {
    final number = value is num ? value : num.tryParse('$value') ?? 0;
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toStringAsFixed(number == number.truncate() ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        backgroundColor: AdminColors.background,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text(
          'Analytics',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: _loading
          ? GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: List.generate(4, (_) => const StatCardSkeleton()),
            )
          : _error != null
          ? _AnalyticsMessage(message: _error!, action: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: _data == null || _data!.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 200),
                        _AnalyticsMessage(
                          message: 'No analytics data available',
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Text(
                          'Dashboard overview',
                          style: Theme.of(context).textTheme.sectionTitle
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Live values from the configured mobile analytics endpoint.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AdminColors.onSurfaceMuted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.2,
                          children: [
                            StaggeredEntrance(
                              index: 0,
                              child: StatCard(
                                label: 'Total users',
                                value: _format(_data!['total_users']),
                                icon: Icons.group_outlined,
                                note: 'All time',
                              ),
                            ),
                            StaggeredEntrance(
                              index: 1,
                              child: StatCard(
                                label: 'Active 7D',
                                value: _format(_data!['active_users_7d']),
                                icon: Icons.timer_outlined,
                                note: '7 days',
                              ),
                            ),
                            StaggeredEntrance(
                              index: 2,
                              child: StatCard(
                                label: 'Courses',
                                value: _format(_data!['total_courses']),
                                icon: Icons.school_outlined,
                                note: 'Live',
                              ),
                            ),
                            StaggeredEntrance(
                              index: 3,
                              child: StatCard(
                                label: 'Questions',
                                value: _format(_data!['total_questions']),
                                icon: Icons.quiz_outlined,
                                note: 'Bank',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AdminColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: AdminColors.outlineVariant,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            'Course, lesson, and vocabulary effectiveness analytics remain web-only because those endpoints are not configured in the mobile admin client.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AdminColors.onSurfaceMuted),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }
}

class _AnalyticsMessage extends StatelessWidget {
  final String message;
  final Future<void> Function()? action;
  const _AnalyticsMessage({required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.query_stats_outlined,
            size: 44,
            color: AdminColors.onSurfaceMuted,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(color: AdminColors.onSurfaceMuted),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: action, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}
