import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_labels.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_thumbnail_resolver.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_category_entity.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Sort options for courses
enum CourseSortOption {
  newest('course.sort.newest', Icons.access_time),
  popular('course.sort.popular', Icons.trending_up),
  alphabetical('course.sort.az', Icons.sort_by_alpha),
  level('course.sort.level', Icons.signal_cellular_alt);

  const CourseSortOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Category Detail Screen
/// Displays all courses within a specific category with view toggle and sort options
class CategoryDetailScreen extends StatefulWidget {
  final String categoryId;

  const CategoryDetailScreen({super.key, required this.categoryId});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  bool _isGridView = false;
  CourseSortOption _sortOption = CourseSortOption.newest;

  @override
  void initState() {
    super.initState();
    // Load courses for this category
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CourseProvider>().loadCoursesByCategory(widget.categoryId);
    });
  }

  /// Sort courses based on selected option
  List<CourseEntity> _sortCourses(List<CourseEntity> courses) {
    final sorted = List<CourseEntity>.from(courses);
    switch (_sortOption) {
      case CourseSortOption.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case CourseSortOption.popular:
        sorted.sort((a, b) => b.totalXp.compareTo(a.totalXp));
        break;
      case CourseSortOption.alphabetical:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case CourseSortOption.level:
        sorted.sort(
          (a, b) =>
              courseLevelOrder(a.level).compareTo(courseLevelOrder(b.level)),
        );
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Consumer<CourseProvider>(
        builder: (context, provider, child) {
          // Find the category safely (never crash when categories are empty)
          CourseCategoryEntity? matchedCategory;
          for (final cat in provider.categories) {
            if (cat.id == widget.categoryId || cat.slug == widget.categoryId) {
              matchedCategory = cat;
              break;
            }
          }
          final category =
              matchedCategory ??
              (provider.categories.isNotEmpty
                  ? provider.categories.first
                  : CourseCategoryEntity(
                      id: widget.categoryId,
                      name: courseCategoryLabelFromSlug(widget.categoryId),
                      slug: widget.categoryId,
                      courseCount: 0,
                    ));

          final categoryColor = courseCategoryColor(
            colorHex: category.color,
            slugOrName: category.slug,
            isDark: isDark,
          );
          final categoryIcon = courseCategoryIcon(
            iconName: category.icon,
            slugOrName: category.slug,
          );
          final categoryTitle = courseCategoryTitle(category);

          // Use the courses loaded for this category
          final categoryCourses = provider.categoryCourses;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: CustomScrollView(
                slivers: [
                  // App Bar with category info
                  SliverAppBar(
                    expandedHeight: 200,
                    pinned: true,
                    backgroundColor: categoryColor,
                    foregroundColor: AppColors.textInverted,
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        categoryTitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.surface,
                          fontWeight: FontWeight.bold,
                          shadows: const [
                            Shadow(
                              color: Colors.black45,
                              offset: Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              categoryColor,
                              categoryColor.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            categoryIcon,
                            size: 80,
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Course count info with view toggle and sort
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'course.coursesAvailablePlural'.plural(
                                categoryCourses.length,
                              ),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: AppColorRoles.textSecondary(isDark),
                                  ),
                            ),
                          ),
                          // Sort dropdown
                          PopupMenuButton<CourseSortOption>(
                            icon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _sortOption.icon,
                                  size: 18,
                                  color: AppColorRoles.textSecondary(isDark),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 18,
                                  color: AppColorRoles.textSecondary(isDark),
                                ),
                              ],
                            ),
                            onSelected: (option) {
                              setState(() => _sortOption = option);
                            },
                            itemBuilder: (context) =>
                                CourseSortOption.values.map((option) {
                                  return PopupMenuItem(
                                    value: option,
                                    child: Row(
                                      children: [
                                        Icon(option.icon, size: 18),
                                        const SizedBox(width: 8),
                                        Text(option.label.tr()),
                                        if (option == _sortOption) ...[
                                          const Spacer(),
                                          const Icon(
                                            Icons.check,
                                            size: 18,
                                            color: AppColors.greenSuccessBright,
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                          ),
                          const SizedBox(width: 8),
                          // View toggle
                          IconButton(
                            icon: Icon(
                              _isGridView ? Icons.view_list : Icons.grid_view,
                              color: AppColorRoles.textSecondary(isDark),
                            ),
                            onPressed: () {
                              setState(() => _isGridView = !_isGridView);
                            },
                            tooltip: _isGridView
                                ? 'course.listView'.tr()
                                : 'course.gridView'.tr(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Course list
                  if (provider.isLoadingCategoryCourses &&
                      categoryCourses.isEmpty)
                    SliverFillRemaining(
                      child: SkeletonList(
                        itemCount: 5,
                        padding: const EdgeInsets.all(16),
                      ),
                    )
                  else if (provider.categoryCoursesError != null &&
                      categoryCourses.isEmpty)
                    SliverFillRemaining(
                      child: ErrorDisplayWidget.fromMessage(
                        message: provider.categoryCoursesError!,
                        onRetry: () =>
                            provider.loadCoursesByCategory(widget.categoryId),
                      ),
                    )
                  else if (categoryCourses.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 64,
                              color: AppColorRoles.textMuted(isDark),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'course.noCourses'.tr(),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: AppColorRoles.textSecondary(isDark),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    // Grid or List view with sorted courses and staggered animation
                    _isGridView
                        ? _buildCourseGrid(_sortCourses(categoryCourses))
                        : _buildCourseList(_sortCourses(categoryCourses)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build list view of courses
  Widget _buildCourseList(List<CourseEntity> courses) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 8,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final course = courses[index];
          return AnimatedListItem(
            index: index,
            duration: const Duration(milliseconds: 300),
            delayPerItem: const Duration(milliseconds: 50),
            child: _CourseCard(
              course: course,
              onTap: () => _navigateToCourseDetail(context, course),
            ),
          );
        }, childCount: courses.length),
      ),
    );
  }

  /// Build grid view of courses
  Widget _buildCourseGrid(List<CourseEntity> courses) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final crossAxisCount = adaptiveColumns(width);

        return SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 8,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.75,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final course = courses[index];
              return AnimatedListItem(
                index: index,
                duration: const Duration(milliseconds: 300),
                delayPerItem: const Duration(milliseconds: 50),
                child: _CourseGridCard(
                  course: course,
                  onTap: () => _navigateToCourseDetail(context, course),
                ),
              );
            }, childCount: courses.length),
          ),
        );
      },
    );
  }

  void _navigateToCourseDetail(BuildContext context, CourseEntity course) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourseDetailScreen(
          courseId: course.id,
          initialThumbnailUrl: course.thumbnailUrl,
          fallbackThumbnailUrl: _courseImageUrl(course),
        ),
      ),
    );
  }
}

String _courseImageUrl(CourseEntity course) {
  final thumbnailUrl = course.thumbnailUrl?.trim();
  if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) return thumbnailUrl;
  return courseFallbackThumbnailUrl(course);
}

/// Course Card Widget for grid view
class _CourseCard extends StatelessWidget {
  final CourseEntity course;
  final VoidCallback onTap;

  const _CourseCard({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Image.network(
                    _courseImageUrl(course),
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    errorBuilder: (_, __, ___) =>
                        _buildPlaceholderImage(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      course.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Description
                    if (course.description != null) ...[
                      Text(
                        course.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorRoles.textSecondary(isDark),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Level + lesson count row
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Builder(
                          builder: (context) {
                            final (bg, fg) = _levelBadgeColors(
                              context,
                              course.level,
                            );
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: Text(
                                courseLevelBadgeLabel(course.level),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: fg,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            );
                          },
                        ),
                        Text(
                          'course.totalLessonsCount'.tr(
                            namedArgs: {'count': '${course.totalLessons}'},
                          ),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColorRoles.textSecondary(isDark),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow icon
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppColorRoles.textMuted(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.surfaceDarkMuted : AppColors.grey200,
      child: Icon(Icons.book, size: 40, color: AppColorRoles.textMuted(isDark)),
    );
  }
}

/// Compact Course Card Widget for grid view
class _CourseGridCard extends StatelessWidget {
  final CourseEntity course;
  final VoidCallback onTap;

  const _CourseGridCard({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.md),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Image.network(
                    _courseImageUrl(course),
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    errorBuilder: (_, __, ___) =>
                        _buildPlaceholderImage(context),
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    course.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Level badge
                  Builder(
                    builder: (context) {
                      final (bg, fg) = _levelBadgeColors(context, course.level);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          courseLevelBadgeLabel(course.level),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.surfaceDarkMuted : AppColors.grey200,
      child: Center(
        child: Icon(
          Icons.book,
          size: 40,
          color: AppColorRoles.textMuted(isDark),
        ),
      ),
    );
  }
}

(Color, Color) _levelBadgeColors(BuildContext context, String level) {
  final status = context.status;
  final scheme = Theme.of(context).colorScheme;
  return switch (level.toLowerCase()) {
    'beginner' ||
    'a1' ||
    'a2' => (status.successContainer, status.onSuccessContainer),
    'intermediate' ||
    'b1' ||
    'b2' => (status.warningContainer, status.onWarningContainer),
    'advanced' ||
    'c1' ||
    'c2' => (scheme.errorContainer, scheme.onErrorContainer),
    _ => (scheme.primaryContainer, scheme.onPrimaryContainer),
  };
}
