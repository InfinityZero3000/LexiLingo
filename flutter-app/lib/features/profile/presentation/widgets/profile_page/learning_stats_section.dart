import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/profile/presentation/pages/learning_stats_pages.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_ui_components.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';

class LearningStatsSection extends StatelessWidget {
  const LearningStatsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primaryColor = AppColorRoles.primary(isDark);
        // Use stats from ProfileProvider (backend API)
        final stats = profileProvider.stats;
        final lessonsCompleted = stats?.totalLessonsCompleted ?? 0;
        final coursesCompleted = stats?.totalCoursesCompleted ?? 0;
        final vocabularyMastered = stats?.totalVocabularyMastered ?? 0;
        final testsPassed = stats?.totalTestsPassed ?? 0;
        final avgScore = stats?.averageTestScore ?? 0.0;

        // Show loading state
        if (profileProvider.isLoadingStats && stats == null) {
          return const _LoadingStats();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.insights_rounded, color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'profile.learningStats'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.abc,
                          color: primaryColor,
                          title: 'profile.lessons'.tr(),
                          value: '$lessonsCompleted',
                          subtitle: 'profile.completed'.tr(),
                          valueInRightCircle: true,
                          valueCircleSize: 40,
                          valueCircleFontSize: 18,
                          isAction: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearningLessonsStatsPage(),
                            ),
                          ),
                          iconBoxSize: 28,
                          iconSize: 14,
                          titleFontSize: 13,
                          subtitleFontSize: 11,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.school,
                          color: primaryColor,
                          title: 'profile.courses'.tr(),
                          value: '$coursesCompleted',
                          subtitle: 'profile.finished'.tr(),
                          valueInRightCircle: true,
                          valueCircleSize: 40,
                          valueCircleFontSize: 18,
                          isAction: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearningCoursesStatsPage(),
                            ),
                          ),
                          iconBoxSize: 28,
                          iconSize: 14,
                          titleFontSize: 13,
                          subtitleFontSize: 11,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.auto_stories,
                          color: primaryColor,
                          title: 'profile.vocabulary'.tr(),
                          value: '$vocabularyMastered',
                          subtitle: 'profile.mastered'.tr(),
                          valueInRightCircle: true,
                          valueCircleSize: 40,
                          valueCircleFontSize: 18,
                          isAction: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const LearningVocabularyStatsPage(),
                            ),
                          ),
                          iconBoxSize: 28,
                          iconSize: 14,
                          titleFontSize: 13,
                          subtitleFontSize: 11,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.quiz,
                          color: primaryColor,
                          title: 'profile.tests'.tr(),
                          value: '$testsPassed',
                          subtitle: avgScore > 0
                              ? 'profile.averagePercent'.tr(
                                  namedArgs: {
                                    'percent': avgScore.toStringAsFixed(0),
                                  },
                                )
                              : 'profile.passed'.tr(),
                          valueInRightCircle: true,
                          valueCircleSize: 40,
                          valueCircleFontSize: 18,
                          isAction: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearningTestsStatsPage(),
                            ),
                          ),
                          iconBoxSize: 28,
                          iconSize: 14,
                          titleFontSize: 13,
                          subtitleFontSize: 11,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
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
      },
    );
  }
}

class _LoadingStats extends StatelessWidget {
  const _LoadingStats();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'profile.learningStats'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: List.generate(
            4,
            (index) => ShimmerContainer(
              child: SkeletonBox(height: double.infinity, borderRadius: 12),
            ),
          ),
        ),
      ],
    );
  }
}
