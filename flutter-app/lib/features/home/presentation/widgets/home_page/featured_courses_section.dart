import 'package:cached_network_image/cached_network_image.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_thumbnail_resolver.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/course_level_helpers.dart';

class FeaturedCoursesEmptyState extends StatelessWidget {
  final HomeProvider provider;

  const FeaturedCoursesEmptyState({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColorRoles.primary(isDark);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.22 : 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_stories_rounded, size: 24, color: primary),
          ),
          const SizedBox(height: 12),
          Text(
            'home.noFeaturedCourses'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'home.noFeaturedCoursesDescription'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColorRoles.textMuted(isDark),
              height: 1.35,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => provider.loadFeaturedCourses(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('home.reload'.tr()),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => provider.refreshData(),
                child: Text('home.refreshData'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FeaturedCourseCard extends StatelessWidget {
  final CourseEntity course;
  final double width;

  const FeaturedCourseCard({super.key, required this.course, this.width = 220});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final levelColor = getLevelColor(course.level, isDark: isDark);
    final tactile =
        theme.extension<AppTactileTheme>() ?? AppTactileTheme.from(theme);

    return GestureDetector(
      onTap: () {
        trackContentInteraction(
          itemType: 'course',
          itemId: course.id,
          action: 'open',
          topic: course.tags.isNotEmpty ? course.tags.first : null,
          source: 'home_featured',
        );
        LearnerRoute.push(
          context,
          (_) => CourseDetailScreen(
            courseId: course.id,
            heroTag: 'featured-course-image-${course.id}',
            initialThumbnailUrl: course.thumbnailUrl,
            fallbackThumbnailUrl: courseFallbackThumbnailUrl(course),
          ),
        );
      },
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: 12),
        decoration: tactile.decoration(
          variant: TactileSurfaceVariant.interactive,
          fill: isDark ? AppColors.surfaceDarkMuted : Colors.white,
          accent: levelColor,
          borderRadius: BorderRadius.circular(16),
          diagnosticId: 'home-featured-course',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'featured-course-image-${course.id}',
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _FeaturedCourseThumbnail(
                        course: course,
                        levelColor: levelColor,
                      ),
                    ),
                    Container(
                      height: 110,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _Badge(
                        color: levelColor,
                        child: Text(
                          localizedCourseLevel(course.level),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.surfaceLight,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _Badge(
                        color: AppColors.orange,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppColors.surfaceLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'profile.xpValue'.tr(
                                namedArgs: {'xp': '${course.totalXp}'},
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.surfaceLight,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 12,
                      right: 12,
                      child: Text(
                        course.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.surfaceLight,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: AppColors.backgroundDark.withValues(
                                alpha: 0.75,
                              ),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.menu_book_rounded,
                          label: 'profile.lessonsCount'.tr(
                            namedArgs: {'count': '${course.totalLessons}'},
                          ),
                          color: AppColorRoles.primaryDeep(isDark),
                        ),
                        const SizedBox(width: 8),
                        _InfoChip(
                          icon: Icons.translate_rounded,
                          label: course.language,
                          color: isDark
                              ? AppColors.purpleLight
                              : AppColors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: levelColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.play_circle_filled_rounded,
                            size: 20,
                            color: AppColors.surfaceLight,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'home.startLearning'.tr(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppColors.surfaceLight,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FeaturedCourseThumbnail extends StatelessWidget {
  final CourseEntity course;
  final Color levelColor;
  final int index;

  const _FeaturedCourseThumbnail({
    required this.course,
    required this.levelColor,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final candidates = buildCourseCardThumbnailCandidates(course);
    if (index >= candidates.length) {
      return _FeaturedCourseThumbnailPlaceholder(levelColor: levelColor);
    }

    return CachedNetworkImage(
      imageUrl: candidates[index],
      cacheKey: 'featured-course-image-${course.id}|${candidates[index]}',
      memCacheWidth: 480,
      fit: BoxFit.cover,
      placeholder: (_, __) =>
          Container(color: levelColor.withValues(alpha: 0.1)),
      errorWidget: (_, __, ___) => _FeaturedCourseThumbnail(
        course: course,
        levelColor: levelColor,
        index: index + 1,
      ),
    );
  }
}

class _FeaturedCourseThumbnailPlaceholder extends StatelessWidget {
  final Color levelColor;

  const _FeaturedCourseThumbnailPlaceholder({required this.levelColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: levelColor.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.school_rounded,
          size: 40,
          color: AppColors.surfaceLight,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
