import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/continue_learning_card.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_data.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_models.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_navigation.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';

/// The one thing to do now: the rotating course card on top, then the words
/// due for review and the next Today's Plan task as two tappable rows.
class NextUpHero extends StatefulWidget {
  const NextUpHero({super.key});

  @override
  State<NextUpHero> createState() => _NextUpHeroState();
}

class _NextUpHeroState extends State<NextUpHero> {
  int? _dueVocabularyCount;
  bool _isLoadingVocabulary = true;

  @override
  void initState() {
    super.initState();
    _loadVocabularyStats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DailyChallengesProvider>().loadChallenges();
    });
  }

  Future<void> _loadVocabularyStats() async {
    final count = await fetchDueVocabularyCount();
    if (!mounted) return;
    setState(() {
      _dueVocabularyCount = count;
      _isLoadingVocabulary = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tactile =
        theme.extension<AppTactileTheme>() ?? AppTactileTheme.from(theme);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: tactile.decoration(
          variant: TactileSurfaceVariant.elevated,
          fill: isDark
              ? theme.colorScheme.surfaceContainerHighest
              : Colors.white,
          accent: AppColorRoles.primary(isDark),
          borderRadius: BorderRadius.circular(24),
          diagnosticId: 'home-next-up',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ContinueLearningCard(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            Consumer3<
              HomeProvider,
              DailyChallengesProvider,
              ProficiencyProvider
            >(
              builder: (context, home, challenges, proficiency, _) {
                final snapshot = buildTodayPlanSnapshot(
                  enrolledCourses: home.enrolledCourses,
                  challenges: challenges.challenges,
                  weakestSkills: proficiency.weakestSkills,
                  dueVocabularyCount: _isLoadingVocabulary
                      ? null
                      : _dueVocabularyCount,
                );
                final vocabulary = snapshot.taskOfType(
                  TodayPlanTaskType.vocabulary,
                );
                final next = snapshot.nextTaskExcluding(
                  TodayPlanTaskType.vocabulary,
                );
                final dueCount = _dueVocabularyCount ?? 0;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'home.nextUp'.tr(),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColorRoles.textMuted(isDark),
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              trackProductEvent(
                                'view_plan_tapped',
                                source: 'today_plan',
                              );
                              Navigator.of(context).pushNamed('/today-plan');
                            },
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                            ),
                            child: Text('home.todayPlan.viewAll'.tr()),
                          ),
                        ],
                      ),
                      if (vocabulary != null)
                        _HeroTaskRow(
                          task: vocabulary,
                          loading: _isLoadingVocabulary,
                          badge: dueCount > 0
                              ? (dueCount > 99 ? '99+' : '$dueCount')
                              : null,
                          onTap: () => openTodayPlanTask(context, vocabulary),
                        ),
                      if (next != null)
                        _HeroTaskRow(
                          task: next,
                          onTap: () => openTodayPlanTask(context, next),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroTaskRow extends StatelessWidget {
  const _HeroTaskRow({
    required this.task,
    required this.onTap,
    this.badge,
    this.loading = false,
  });

  final TodayPlanTask task;
  final VoidCallback onTap;
  final String? badge;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = AppColorRoles.textMuted(isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: task.color.withValues(alpha: isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(task.icon, color: task.color, size: 21),
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (loading)
                      const SizedBox(
                        width: 48,
                        child: LinearProgressIndicator(minHeight: 3),
                      )
                    else
                      Text(
                        task.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: task.color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                task.isCompleted
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: task.isCompleted ? task.color : muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
