import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

/// The one thing most learners open the app for: pick up the course they are
/// part-way through. Renders nothing until they are enrolled somewhere.
class ContinueLearningCard extends StatelessWidget {
  const ContinueLearningCard({super.key});

  static CourseEntity? pick(List<CourseEntity> enrolled) {
    if (enrolled.isEmpty) return null;
    return enrolled.firstWhere(
      (c) => (c.userProgress ?? 0) < 100,
      orElse: () => enrolled.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final course = pick(context.watch<HomeProvider>().enrolledCourses);
    if (course == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final fill = isDark ? scheme.surfaceContainerHighest : AppColors.primary;
    final fg = isDark ? scheme.onSurface : Colors.white;
    final track = fg.withValues(alpha: 0.24);
    final progress = ((course.userProgress ?? 0) / 100).clamp(0.0, 1.0);

    void open() {
      trackContentInteraction(
        itemType: 'course',
        itemId: course.id,
        action: 'open',
        topic: course.tags.isNotEmpty ? course.tags.first : null,
        source: 'home_continue',
      );
      LearnerRoute.push(
        context,
        (_) => CourseDetailScreen(courseId: course.id),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: fg.withValues(alpha: 0.18),
                        border: Border.all(
                          color: fg.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        PhosphorIconsBold.bookOpenText,
                        color: fg,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'home.continueLearningSection'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            course.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: progress,
                          backgroundColor: track,
                          valueColor: AlwaysStoppedAnimation<Color>(fg),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${(progress * 100).round()}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: open,
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? AppColorRoles.primary(true)
                          : fg,
                      foregroundColor: isDark ? scheme.surface : fill,
                      shape: const StadiumBorder(),
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(PhosphorIconsBold.caretRight, size: 18),
                    label: Text(
                      'home.continueLesson'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
