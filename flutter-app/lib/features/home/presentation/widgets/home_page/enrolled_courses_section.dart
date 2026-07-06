import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/course_level_helpers.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';

class EnrolledCoursesSection extends StatelessWidget {
  const EnrolledCoursesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();

    // Show loading state if courses are being loaded
    if (provider.isLoading && provider.enrolledCourses.isEmpty) {
      return SizedBox(
        height: 126, // Slightly increased to match card content height
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 2,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(right: 16),
              width: 240, // Reduced from 296 roughly
              child: const CardSkeleton(isHorizontal: true),
            );
          },
        ),
      );
    }

    // Show empty state if no enrolled courses
    if (provider.enrolledCourses.isEmpty) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDarkMuted : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.slate200,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.school_outlined,
                size: 48,
                color: isDark ? AppColors.textMuted : AppColors.textGrey,
              ),
              const SizedBox(height: 12),
              Text(
                'home.noEnrolledCoursesYet'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textInverted : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'home.enrollCoursePrompt'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.textMuted : AppColors.textGrey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Show enrolled courses
    return SizedBox(
      height: 136,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: provider.enrolledCourses.length,
        itemBuilder: (context, index) {
          final course = provider.enrolledCourses[index];
          // Staggered animation for enrolled courses
          return AnimatedListItem(
            index: index,
            duration: const Duration(milliseconds: 300),
            delayPerItem: const Duration(milliseconds: 80),
            child: _EnrolledCourseCard(course: course),
          );
        },
      ),
    );
  }
}

class _EnrolledCourseCard extends StatelessWidget {
  final CourseEntity course;

  const _EnrolledCourseCard({required this.course});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = course.userProgress ?? 0;
    final progressColor = progress >= 80
        ? AppColors.greenSuccessBright
        : progress >= 50
        ? AppColors.orange
        : AppColorRoles.primary(isDark);
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceBg = colorScheme.surfaceContainerHighest;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(courseId: course.id),
          ),
        );
      },
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: surfaceBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: progressColor.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Course thumbnail
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colorScheme.surface,
                  image: course.thumbnailUrl != null
                      ? DecorationImage(
                          image: NetworkImage(course.thumbnailUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: course.thumbnailUrl == null
                    ? Icon(Icons.school, size: 32, color: progressColor)
                    : null,
              ),
              const SizedBox(width: 16),
              // Info section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      course.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: progressColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            localizedCourseLevel(course.level),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: progressColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'profile.lessonsCount'.tr(
                            namedArgs: {'count': '${course.totalLessons}'},
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColorRoles.textSecondary(isDark),
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Progress bar
                    Stack(
                      children: [
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: progressColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress / 100,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  progressColor,
                                  progressColor.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${progress.toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: progressColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                progressColor,
                                progressColor.withValues(alpha: 0.8),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: progressColor.withValues(alpha: 0.4),
                                blurRadius: 0,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 16,
                            color: AppColors.surfaceLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
