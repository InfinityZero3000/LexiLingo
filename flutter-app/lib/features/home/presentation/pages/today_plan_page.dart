import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_models.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_navigation.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_section.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart'
    as vocab_di;

class TodayPlanPage extends StatefulWidget {
  const TodayPlanPage({super.key});

  @override
  State<TodayPlanPage> createState() => _TodayPlanPageState();
}

class _TodayPlanPageState extends State<TodayPlanPage> {
  int? _dueVocabularyCount;
  bool _isLoadingVocabulary = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadVocabularyStats(),
      context.read<DailyChallengesProvider>().refresh(),
      context.read<ProficiencyProvider>().loadProfile(),
    ]);
  }

  Future<void> _loadVocabularyStats() async {
    if (mounted) {
      setState(() => _isLoadingVocabulary = true);
    }

    final result = await vocab_di
        .getIt<VocabularyRepository>()
        .getVocabularyStats();

    if (!mounted) return;

    setState(() {
      _dueVocabularyCount = result.fold(
        (_) => null,
        (stats) => stats['due_for_review'] as int? ?? 0,
      );
      _isLoadingVocabulary = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);

    return Scaffold(
      appBar: AppBar(
        title: Text('home.todayPlan.title'.tr()),
        leading: AppBackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body:
          Consumer3<HomeProvider, DailyChallengesProvider, ProficiencyProvider>(
            builder: (context, home, challenges, proficiency, _) {
              final snapshot = buildTodayPlanSnapshot(
                enrolledCourses: home.enrolledCourses,
                challenges: challenges.challenges,
                weakestSkills: proficiency.weakestSkills,
                dueVocabularyCount: _isLoadingVocabulary
                    ? null
                    : _dueVocabularyCount,
              );
              final nextTask = snapshot.nextTask;

              return RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([home.refreshData(), _loadData()]);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _TodayPlanHero(snapshot: snapshot, color: accent),
                    const SizedBox(height: 16),
                    if (nextTask != null)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () => openTodayPlanTask(context, nextTask),
                          icon: Icon(nextTask.icon),
                          label: Text('home.todayPlan.startNext'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      'home.todayPlan.sequenceTitle'.tr(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...snapshot.tasks.map(
                      (task) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TodayPlanTaskTile(
                          task: task,
                          onTap: () => openTodayPlanTask(context, task),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }
}

class _TodayPlanHero extends StatelessWidget {
  const _TodayPlanHero({required this.snapshot, required this.color});

  final TodayPlanSnapshot snapshot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.74)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.24 : 0.20),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.route_rounded,
                  color: colorScheme.surface,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'home.todayPlan.heroTitle'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colorScheme.surface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'home.todayPlan.heroSubtitle'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.surface.withValues(alpha: 0.88),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: snapshot.progress,
              backgroundColor: colorScheme.surface.withValues(alpha: 0.20),
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.surface),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'home.todayPlan.completedSummary'.tr(
              namedArgs: {
                'completed': '${snapshot.completedCount}',
                'total': '${snapshot.totalCount}',
              },
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.surface.withValues(alpha: 0.86),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
