import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_models.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_navigation.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart'
    as vocab_di;

class TodayPlanSection extends StatefulWidget {
  const TodayPlanSection({super.key});

  @override
  State<TodayPlanSection> createState() => _TodayPlanSectionState();
}

class _TodayPlanSectionState extends State<TodayPlanSection> {
  int? _dueVocabularyCount;
  bool _isLoadingVocabulary = true;

  @override
  void initState() {
    super.initState();
    _loadVocabularyStats();
  }

  Future<void> _loadVocabularyStats() async {
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
    final colorScheme = Theme.of(context).colorScheme;
    final accent = AppColorRoles.primary(isDark);

    return Consumer3<
      HomeProvider,
      DailyChallengesProvider,
      ProficiencyProvider
    >(
      builder: (context, home, challenges, proficiency, _) {
        final snapshot = buildTodayPlanSnapshot(
          enrolledCourses: home.enrolledCourses,
          challenges: challenges.challenges,
          weakestSkills: proficiency.weakestSkills,
          dueVocabularyCount: _isLoadingVocabulary ? null : _dueVocabularyCount,
        );
        final visibleTasks = snapshot.tasks.take(3).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).pushNamed('/today-plan'),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: Theme.of(context)
                    .extension<AppTactileTheme>()!
                    .decoration(
                      variant: TactileSurfaceVariant.interactive,
                      fill: isDark
                          ? colorScheme.surfaceContainerHighest
                          : Colors.white,
                      accent: accent,
                      borderRadius: BorderRadius.circular(20),
                      diagnosticId: 'home-today-plan',
                    ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.route_rounded,
                            color: accent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'home.todayPlan.title'.tr(),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'home.todayPlan.subtitle'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppColorRoles.textMuted(isDark),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        _PlanProgressPill(snapshot: snapshot, color: accent),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: snapshot.progress,
                        backgroundColor: accent.withValues(alpha: 0.14),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...visibleTasks.map(
                      (task) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TodayPlanTaskTile(
                          task: task,
                          dense: true,
                          onTap: () => openTodayPlanTask(context, task),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'home.todayPlan.footer'.tr(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColorRoles.textMuted(isDark),
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/today-plan'),
                          child: Text('home.todayPlan.viewAll'.tr()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlanProgressPill extends StatelessWidget {
  const _PlanProgressPill({required this.snapshot, required this.color});

  final TodayPlanSnapshot snapshot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${snapshot.completedCount}/${snapshot.totalCount}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class TodayPlanTaskTile extends StatelessWidget {
  const TodayPlanTaskTile({super.key, required this.task, required this.onTap});

  final TodayPlanTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TodayPlanTaskTile(task: task, onTap: onTap);
  }
}

class _TodayPlanTaskTile extends StatelessWidget {
  const _TodayPlanTaskTile({
    required this.task,
    required this.onTap,
    this.dense = false,
  });

  final TodayPlanTask task;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final muted = AppColorRoles.textMuted(isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(dense ? 10 : 14),
          decoration: BoxDecoration(
            color: task.isCompleted
                ? task.color.withValues(alpha: 0.10)
                : colorScheme.surface.withValues(alpha: isDark ? 0.36 : 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: task.isCompleted
                  ? task.color.withValues(alpha: 0.32)
                  : colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: dense ? 40 : 48,
                height: dense ? 40 : 48,
                decoration: BoxDecoration(
                  color: task.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  task.icon,
                  color: task.color,
                  size: dense ? 21 : 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.subtitle,
                      maxLines: dense ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    if (!dense) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          value: task.progress,
                          backgroundColor: task.color.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(task.color),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (task.rewardLabel != null)
                    Text(
                      task.rewardLabel!,
                      style: TextStyle(
                        color: task.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (task.metaLabel != null)
                    Text(
                      task.metaLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 5),
                  Icon(
                    task.isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.arrow_forward_ios_rounded,
                    color: task.isCompleted ? task.color : muted,
                    size: task.isCompleted ? 18 : 14,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
