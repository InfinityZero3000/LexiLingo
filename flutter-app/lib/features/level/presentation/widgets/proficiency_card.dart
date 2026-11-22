import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/pages/main_screen.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/level/presentation/widgets/proficiency_radar_chart.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Proficiency card with radar chart for profile page
/// Shows 5 proficiency dimensions evaluated by AI from conversations
class ProficiencyCard extends StatelessWidget {
  const ProficiencyCard({super.key});

  /// Minimum lessons/interactions before scores are shown
  static const int unlockThreshold = 15;

  static const _radarSkills = [
    SkillType.listening,
    SkillType.speaking,
    SkillType.reading,
    SkillType.writing,
    SkillType.vocabulary,
    SkillType.grammar,
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<ProficiencyProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading &&
            provider.profile == ProficiencyProfile.empty()) {
          return _buildLoadingState(context);
        }

        return _buildContent(context, provider);
      },
    );
  }

  Widget _buildContent(BuildContext context, ProficiencyProvider provider) {
    final profile = provider.profile;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    final hasEnoughData =
        profile.exercisesCompleted >= unlockThreshold ||
        profile.lessonsCompleted >= unlockThreshold;

    // Backend scores are 0-100; the chart draws 0-1.
    final displayScores = {
      for (final skill in _radarSkills)
        skill.displayName: (profile.skills[skill]?.score ?? 0) / 100,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Text(
            'profile.yourProficiency'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? accent.withValues(alpha: 0.22)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              // Description text
              if (!hasEnoughData) ...[
                Text(
                  'profile.proficiencyUnlockHint'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Radar chart with center icon
              Center(
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ProficiencyRadarChart(
                        scores: hasEnoughData
                            ? displayScores
                            : {
                                for (final skill in _radarSkills)
                                  skill.displayName: 0.0,
                              },
                        size: 240,
                        fillColor: isDark
                            ? accent.withValues(alpha: 0.25)
                            : Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.15),

                        strokeColor: accent,
                        gridColor: isDark
                            ? AppColors.onGradient.withValues(alpha: 0.1)
                            : Theme.of(context).colorScheme.outlineVariant,

                        animate: true,
                      ),
                      // Center decorative icon
                      if (!hasEnoughData)
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDarkMuted.withValues(
                                    alpha: 0.9,
                                  )
                                : AppColors.onGradient.withValues(alpha: 0.9),

                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? accent.withValues(alpha: 0.3)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,

                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.hourglass_bottom_rounded,
                            size: 28,
                            color: isDark
                                ? accent.withValues(alpha: 0.6)
                                : accent.withValues(alpha: 0.4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Unlock message
              if (!hasEnoughData) ...[
                Text(
                  'profile.proficiencyUnlockThreshold'.tr(
                    namedArgs: {'count': '$unlockThreshold'},
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Action buttons
              Row(
                children: [
                  // Placement test button
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: () async {
                        final confirmed = await _confirmStartTest(context);
                        if (confirmed != true || !context.mounted) return;
                        await Navigator.pushNamed(context, '/placement-test');
                        if (context.mounted) {
                          await context
                              .read<ProficiencyProvider>()
                              .loadProfile();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.onGradient.withValues(alpha: 0.1)
                              : AppColors.grey100,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: isDark
                                ? AppColors.onGradient.withValues(alpha: 0.15)
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.quiz_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'assessment.placementTest'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.onGradient
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Start Lessons button
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MainScreen(initialIndex: 1),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'profile.startLessons'.tr(),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppColors.surfaceLight,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool?> _confirmStartTest(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('assessment.confirmStartTitle'.tr()),
        content: Text('assessment.confirmStartMessage'.tr()),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('assessment.startNow'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Text(
            'profile.yourProficiency'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? accent.withValues(alpha: 0.22)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: const Center(
            child: ShimmerContainer(child: SkeletonCircle(size: 160)),
          ),
        ),
      ],
    );
  }
}
