import 'package:lexilingo_app/core/l10n/relative_time.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Course Progress Card Widget
/// Displays progress for a single course
class CourseProgressCard extends StatelessWidget {
  final CourseProgressDetail courseProgress;
  final VoidCallback? onTap;

  const CourseProgressCard({
    super.key,
    required this.courseProgress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progressPercent = (courseProgress.progressPercentage / 100);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Course Title & XP
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      courseProgress.courseTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.star, size: 16, color: AppColors.goldDark),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '${courseProgress.totalXpEarned} XP',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.goldDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // Progress Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'course.userProgressPercent'.tr(
                          namedArgs: {
                            'percent': courseProgress.progressPercentage
                                .toStringAsFixed(1),
                          },
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'progress.lessonsOfTotal'.tr(
                          namedArgs: {
                            'completed': '${courseProgress.lessonsCompleted}',
                            'total': '${courseProgress.totalLessons}',
                          },
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progressPercent),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, __) => LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getProgressColor(
                            courseProgress.progressPercentage,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: AppSpacing.md),

              // Last Activity
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'progress.lastActivity'.tr(
                        namedArgs: {
                          'date': _formatDate(courseProgress.lastActivityAt),
                        },
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getProgressColor(double progress, {bool isDark = false}) {
    if (progress >= 80) {
      return AppColors.greenSuccessBright;
    } else if (progress >= 50) {
      return AppColors.orange;
    } else {
      return AppColorRoles.primary(isDark);
    }
  }

  String _formatDate(DateTime date) => relativeTime(date);
}
