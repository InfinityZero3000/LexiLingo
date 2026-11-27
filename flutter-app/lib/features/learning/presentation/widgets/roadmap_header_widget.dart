import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Roadmap Header Widget
/// Displays course info, progress stats, and streak at the top of roadmap
class RoadmapHeaderWidget extends StatelessWidget {
  final CourseRoadmap roadmap;
  final VoidCallback onBack;

  const RoadmapHeaderWidget({
    super.key,
    required this.roadmap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryAccent = AppColorRoles.primary(isDark);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  AppBackButton(
                    icon: Icons.arrow_back,
                    color: AppColors.surfaceLight,
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Text(
                      roadmap.courseTitle,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.surfaceLight,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildLevelBadge(context, roadmap.level),
                ],
              ),
            ),

            // Progress stats
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem(
                    context,
                    icon: Icons.local_fire_department,
                    value: '${roadmap.currentStreak}',
                    label: 'common.streak'.tr(),
                    iconColor: AppColors.orange,
                  ),
                  _buildStatItem(
                    context,
                    icon: Icons.star,
                    value: '${roadmap.totalXpEarned}',
                    label: 'XP',
                    iconColor: context.status.warning,
                  ),
                  _buildStatItem(
                    context,
                    icon: Icons.check_circle,
                    value:
                        '${roadmap.completedLessons}/${roadmap.totalLessons}',
                    label: 'course.lessons'.tr(),
                    iconColor: context.status.success,
                  ),
                  _buildStatItem(
                    context,
                    icon: Icons.pie_chart,
                    value:
                        '${roadmap.completionPercentage.toStringAsFixed(0)}%',
                    label: 'profile.progress'.tr(),
                    iconColor: primaryAccent,
                  ),
                ],
              ),
            ),

            // Overall progress bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'learning.courseProgress'.tr(),
                          style: Theme.of(context).textTheme.bodySmall!
                              .copyWith(color: Colors.white70),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${roadmap.completionPercentage.toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: AppColors.surfaceLight,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: LinearProgressIndicator(
                      value: roadmap.completionPercentage / 100,
                      minHeight: 8,
                      // A solid white track made 0% look complete.
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Curved bottom
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.xl),
                  topRight: Radius.circular(AppRadius.xl),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelBadge(BuildContext context, String level) {
    Color badgeColor;
    switch (level.toLowerCase()) {
      case 'beginner':
        badgeColor = context.status.success;
        break;
      case 'intermediate':
        badgeColor = AppColors.orange;
        break;
      case 'advanced':
        badgeColor = Theme.of(context).colorScheme.error;
        break;
      default:
        // CEFR codes: the header itself is primary, so primary was invisible.
        badgeColor = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: badgeColor, width: AppBorderWidth.hairline),
      ),
      child: Text(
        level.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          fontWeight: FontWeight.bold,
          color: badgeColor,
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
  }) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.surfaceLight,
              ),
            ),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: AppColors.surfaceLight),
            ),
          ],
        ),
      ),
    );
  }
}
