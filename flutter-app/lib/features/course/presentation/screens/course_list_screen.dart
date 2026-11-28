import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/tap_target.dart';
// ignore: depend_on_referenced_packages
import 'package:lexilingo_app/core/network/course_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/pages/main_screen.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/presentation/screens/category_detail_screen.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_labels.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_thumbnail_resolver.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_category_entity.dart';
import 'package:lexilingo_app/core/widgets/app_surface.dart';

/// Course List Screen
/// Displays courses in horizontal scrolling sections grouped by category
/// Decorative cover gradients; picked by course-id hash, fixed in both themes.
const _courseCardGradients = <List<Color>>[
  [AppColors.primary, AppColors.purple],
  [AppColors.purple, AppColors.pink],
  [AppColors.primary, AppColors.teal],
  [AppColors.greenSuccessBright, AppColors.teal],
  [AppColors.pink, AppColors.orange],
  [AppColors.teal, AppColors.purple],
  [AppColors.orange, AppColors.accentYellow],
  [AppColors.purpleLight, AppColors.pink],
];

class CourseListScreen extends StatefulWidget {
  const CourseListScreen({super.key});

  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Load categories and courses
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CourseProvider>();
      provider.loadCategories();
      provider.loadCourses();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<CourseEntity>? _sectionsCourses;
  List<CourseCategoryEntity>? _sectionsCategories;
  List<MapEntry<CourseCategoryEntity, List<CourseEntity>>> _sections = const [];

  // Grouping is O(categories x courses x tags); redo it only when the inputs
  // change, not on every provider notification.
  // Each course is assigned to at most ONE primary category shelf on the
  // discovery screen (preferring explicit categoryId, then first matching tag)
  // so the same course card never repeats across adjacent shelves.
  List<MapEntry<CourseCategoryEntity, List<CourseEntity>>> _sectionsFor(
    List<CourseEntity> courses,
    List<CourseCategoryEntity> categories,
  ) {
    if (identical(courses, _sectionsCourses) &&
        identical(categories, _sectionsCategories)) {
      return _sections;
    }
    final buckets = <String, List<CourseEntity>>{
      for (final category in categories) category.id: <CourseEntity>[],
    };
    final byId = <String, CourseCategoryEntity>{
      for (final category in categories) category.id: category,
    };
    final bySlug = <String, CourseCategoryEntity>{
      for (final category in categories)
        category.slug.trim().toLowerCase(): category,
      for (final category in categories)
        category.name.trim().toLowerCase(): category,
    };
    final generalCategory = bySlug['general'];

    for (final course in courses) {
      CourseCategoryEntity? primary;

      // 1. Explicit category_id link
      final catId = course.categoryId;
      if (catId != null && catId.isNotEmpty) {
        primary = byId[catId] ?? bySlug[catId.toLowerCase()];
      }

      // 2. First tag in course.tags order that maps to a known category
      if (primary == null) {
        for (final rawTag in course.tags) {
          final tag = rawTag.trim().toLowerCase();
          final matchedCat = bySlug[tag];
          if (matchedCat != null) {
            primary = matchedCat;
            break;
          }
        }
      }

      // 3. Fallback to 'general' category if untagged
      primary ??= (course.tags.isEmpty ? generalCategory : null);

      if (primary != null) {
        buckets[primary.id]!.add(course);
      }
    }

    final result = <MapEntry<CourseCategoryEntity, List<CourseEntity>>>[];
    for (final category in categories) {
      final matched = buckets[category.id]!;
      if (matched.isNotEmpty) {
        result.add(MapEntry(category, matched));
      }
    }
    _sectionsCourses = courses;
    _sectionsCategories = categories;
    return _sections = result;
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      context.read<CourseProvider>().loadMoreCourses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryAccent = AppColorRoles.primary(isDark);

    return Scaffold(
      body: Consumer<CourseProvider>(
        builder: (context, provider, child) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([
                    provider.refreshCourses(),
                    provider.loadCategories(),
                  ]);
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Keep the complete course header visible while scrolling.
                    SliverAppBar(
                      toolbarHeight: 92,
                      pinned: true,
                      backgroundColor: Theme.of(
                        context,
                      ).scaffoldBackgroundColor,
                      surfaceTintColor: Colors.transparent,
                      scrolledUnderElevation: 0,
                      automaticallyImplyLeading: false,
                      titleSpacing: 0,
                      title: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          AppSpacing.sm,
                          20,
                          0,
                        ),
                        child: Row(
                          children: [
                            // A tab in MainScreen, but also pushed as a
                            // route (Today Plan) — only then can it pop.
                            if (ModalRoute.of(context)?.canPop ?? false)
                              AppBackButton(
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: primaryAccent,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: Icon(
                                Icons.explore,
                                color: Theme.of(context).colorScheme.surface,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'course.discoverCourses'.tr(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'course.coursesAvailablePlural'.plural(
                                      provider.filteredCourses.length,
                                    ),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: provider.hasActiveFilters
                                        ? primaryAccent
                                        : primaryAccent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.tune_rounded,
                                      color: provider.hasActiveFilters
                                          ? AppColors.textInverted
                                          : primaryAccent,
                                    ),
                                    onPressed: () => _showFilterSheet(context),
                                    tooltip: 'common.filter'.tr(),
                                  ),
                                ),
                                if (provider.hasActiveFilters)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: AppColors.warning,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).scaffoldBackgroundColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Hero banner below heading
                    const SliverToBoxAdapter(child: _CourseBanner()),

                    // Quick filter rail (levels, enrolled, clear)
                    SliverToBoxAdapter(
                      child: _QuickFilterBar(provider: provider),
                    ),

                    // Content
                    if ((provider.isLoadingCourses ||
                            provider.isLoadingCategories) &&
                        provider.courses.isEmpty &&
                        provider.categories.isEmpty)
                      const SliverFillRemaining(
                        child: Center(child: LottieLoadingWidget.medium()),
                      )
                    else if (provider.coursesError != null &&
                        provider.courses.isEmpty)
                      SliverFillRemaining(
                        child: ErrorDisplayWidget.fromMessage(
                          message: provider.coursesError!,
                          onRetry: () {
                            provider.refreshCourses();
                            provider.loadCategories();
                          },
                        ),
                      )
                    else if (provider.courses.isEmpty &&
                        !provider.hasActiveFilters)
                      SliverFillRemaining(child: EmptyStateWidget.courses())
                    else
                      SliverPadding(
                        padding: EdgeInsets.only(
                          bottom: MainScreen.bottomBarClearance(context),
                        ),
                        sliver: _buildCourseContent(context, provider),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCourseContent(BuildContext context, CourseProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayCourses = provider.filteredCourses;

    // Show empty-filtered state when server or client-side filters result in nothing
    if (displayCourses.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyStateWidget.searchResults(),
            if (provider.hasActiveFilters) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => provider.clearFilters(),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: Text('common.clear'.tr()),
              ),
            ],
          ],
        ),
      );
    }

    final categories = provider.categories;
    final nonEmptyCategorySections = _sectionsFor(displayCourses, categories);
    final mappedCourseIds = <String>{
      for (final e in nonEmptyCategorySections) ...e.value.map((c) => c.id),
    };

    final totalCourses = displayCourses.length;
    final mappingCoverage = totalCourses == 0
        ? 0.0
        : mappedCourseIds.length / totalCourses;

    final shouldUseCategories =
        categories.isNotEmpty &&
        nonEmptyCategorySections.isNotEmpty &&
        mappingCoverage >= 0.6;

    // When client-side sort is active, skip category grouping and show flat list
    final forceFlat = provider.sortOrder != 'default';

    if (forceFlat || !shouldUseCategories) {
      // Flat grouped-by-level list, ordered from A1 -> C2
      final grouped = <String, List<CourseEntity>>{};
      for (final course in displayCourses) {
        grouped.putIfAbsent(course.level, () => []).add(course);
      }
      final levelKeys = grouped.keys.toList()
        ..sort((a, b) => courseLevelOrder(a).compareTo(courseLevelOrder(b)));

      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == levelKeys.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: LottieLoadingWidget.small(),
              ),
            );
          }
          final levelKey = levelKeys[index];
          final courses = grouped[levelKey]!;
          return _CategorySection(
            categoryId: levelKey,
            categorySlug: null,
            title: courseLevelBadgeLabel(levelKey),
            description: 'course.courseCount'.plural(courses.length),
            icon: _getLevelIcon(levelKey),
            color: courseLevelColor(levelKey, isDark: isDark),
            courses: courses,
            onCourseTap: (course, heroTag, fallbackThumbnailUrl) =>
                _navigateToCourseDetail(
                  context,
                  course,
                  heroTag,
                  fallbackThumbnailUrl,
                ),
            onSeeAll: null,
          );
        }, childCount: levelKeys.length + (provider.isLoadingCourses ? 1 : 0)),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == nonEmptyCategorySections.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: LottieLoadingWidget.small(),
              ),
            );
          }

          final section = nonEmptyCategorySections[index];
          final category = section.key;
          final categoryCourses = section.value;

          return _CategorySection(
            categoryId: category.id,
            categorySlug: category.slug,
            title: courseCategoryTitle(category),
            description: 'course.courseCount'.plural(categoryCourses.length),
            icon: courseCategoryIcon(
              iconName: category.icon,
              slugOrName: category.slug,
            ),
            color: courseCategoryColor(
              colorHex: category.color,
              slugOrName: category.slug,
              isDark: isDark,
            ),
            courses: categoryCourses,
            onCourseTap: (course, heroTag, fallbackThumbnailUrl) =>
                _navigateToCourseDetail(
                  context,
                  course,
                  heroTag,
                  fallbackThumbnailUrl,
                ),
            onSeeAll: () => _navigateToCategoryDetail(context, category.id),
          );
        },
        childCount:
            nonEmptyCategorySections.length +
            (provider.isLoadingCourses ? 1 : 0),
      ),
    );
  }

  void _navigateToCourseDetail(
    BuildContext context,
    CourseEntity course,
    String heroTag,
    String fallbackThumbnailUrl,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourseDetailScreen(
          courseId: course.id,
          heroTag: heroTag,
          initialThumbnailUrl: course.thumbnailUrl,
          fallbackThumbnailUrl: fallbackThumbnailUrl,
        ),
      ),
    );
  }

  void _navigateToCategoryDetail(BuildContext context, String categoryId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryDetailScreen(categoryId: categoryId),
      ),
    );
  }

  IconData _getLevelIcon(String level) {
    final code = courseCefrCode(level);
    switch (code) {
      case 'A1':
      case 'A2':
        return Icons.school_outlined;
      case 'B1':
      case 'B2':
        return Icons.trending_up;
      case 'C1':
      case 'C2':
        return Icons.emoji_events_outlined;
      default:
        return Icons.book_outlined;
    }
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => const _FilterSheet(),
    );
  }
}

/// Hero banner displayed at the top of the course discovery screen
class _CourseBanner extends StatelessWidget {
  const _CourseBanner();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Stack(
          children: [
            // Banner image
            Image.asset(
              'assets/course/banner_course.webp',
              width: double.infinity,
              height: 88,
              fit: BoxFit.cover,
            ),
            // Subtle overlay so text is readable
            Container(
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    (isDark ? AppColors.slate900 : AppColors.primaryDark)
                        .withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Text overlay
            Positioned(
              right: 20,
              top: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'course.startLearning'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textInverted,

                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: AppColors.slate900.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'course.pickCoursePrompt'.tr(),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textInverted.withValues(alpha: 0.9),

                      height: 1.4,
                      shadows: [
                        Shadow(
                          color: AppColors.slate900.withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick horizontal filter bar below the hero banner for 1-tap CEFR level
/// and enrolled-course filtering without opening the modal sheet.
class _QuickFilterBar extends StatelessWidget {
  final CourseProvider provider;

  const _QuickFilterBar({required this.provider});

  static const List<String> _cefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColorRoles.primary(isDark);
    final selectedLevel = provider.selectedLevel;
    final enrolledOnly = provider.showEnrolledOnly;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          children: [
            // "All" pill
            _QuickPill(
              label: 'course.langAll'.tr(),
              isSelected: !provider.hasActiveFilters,
              color: primary,
              onTap: () {
                if (provider.hasActiveFilters) {
                  provider.clearFilters();
                }
              },
            ),
            const SizedBox(width: 8),

            // "My Enrollments" pill
            _QuickPill(
              label: 'course.myEnrollments'.tr(),
              icon: Icons.school_rounded,
              isSelected: enrolledOnly,
              color: AppColors.warningDark,
              onTap: () {
                provider.setClientFilters(enrolledOnly: !enrolledOnly);
              },
            ),
            const SizedBox(width: 8),

            // CEFR level pills
            for (final lvl in _cefrLevels) ...[
              _QuickPill(
                label: courseLevelBadgeLabel(lvl),
                isSelected: selectedLevel?.toUpperCase() == lvl,
                color: courseLevelColor(lvl, isDark: isDark),
                onTap: () {
                  final next = selectedLevel?.toUpperCase() == lvl ? null : lvl;
                  provider.filterByLevel(next);
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _QuickPill({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : color.withValues(alpha: isDark ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? AppColors.textInverted : color,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isSelected ? AppColors.textInverted : color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Category Section Widget
/// Displays a category title with horizontally scrolling course cards
class _CategorySection extends StatelessWidget {
  final String categoryId;
  final String? categorySlug;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<CourseEntity> courses;
  final void Function(
    CourseEntity course,
    String heroTag,
    String fallbackThumbnailUrl,
  )
  onCourseTap;
  final VoidCallback? onSeeAll;

  const _CategorySection({
    required this.categoryId,
    this.categorySlug,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.courses,
    required this.onCourseTap,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactMobile = screenWidth < 390;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header
        Padding(
          padding: EdgeInsets.fromLTRB(
            isCompactMobile ? 14 : AppSpacing.lg,
            isCompactMobile ? 8 : 10,
            isCompactMobile ? 10 : AppSpacing.md,
            isCompactMobile ? 6 : AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isCompactMobile ? 8 : 9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: isCompactMobile ? 18 : 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'common.seeAll'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded, size: 18, color: color),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Horizontal Course List
        SizedBox(
          height: isCompactMobile ? 226 : 254,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: isCompactMobile ? 10 : AppSpacing.md,
            ),
            itemCount: courses.length,
            itemExtent: (isCompactMobile ? 160.0 : 182.0) + 8,
            cacheExtent: 400,
            itemBuilder: (context, index) {
              final course = courses[index];
              // Scope Hero tag to this section to keep Hero tags unique.
              final heroTag = 'discovery-course-image-$categoryId-${course.id}';
              return RepaintBoundary(
                child: _HorizontalCourseCard(
                  key: ValueKey(heroTag),
                  course: course,
                  categorySlug: categorySlug,
                  heroTag: heroTag,
                  compact: isCompactMobile,
                  onTap: (fallbackThumbnailUrl) =>
                      onCourseTap(course, heroTag, fallbackThumbnailUrl),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 10),
      ],
    );
  }
}

/// Horizontal Course Card Widget
/// Compact card design for horizontal scrolling with enhanced hero images
class _HorizontalCourseCard extends StatelessWidget {
  final CourseEntity course;
  final String? categorySlug;
  final String heroTag;
  final bool compact;
  final ValueChanged<String> onTap;

  const _HorizontalCourseCard({
    super.key,
    required this.course,
    this.categorySlug,
    required this.heroTag,
    this.compact = false,
    required this.onTap,
  });

  String get _fallbackUrl => courseFallbackThumbnailUrl(
    course,
    preferredCategorySlug: categorySlug,
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardWidth = compact ? 160.0 : 182.0;
    const cardRadius = AppRadius.lg;
    final contentPadding = compact ? 10.0 : 12.0;
    final imageAspectRatio = compact ? 16 / 9 : 16 / 10;
    final levelColor = courseLevelColor(course.level, isDark: isDark);

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      child: AppSurface(
        radius: BorderRadius.circular(cardRadius),
        onTap: () => onTap(_fallbackUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enhanced Hero Thumbnail with subtle top scrim behind badge
            Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(cardRadius),
                ),
                child: AspectRatio(
                  aspectRatio: imageAspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background image or placeholder
                      _buildCourseThumbnail(context),

                      // Top scrim where the CEFR badge actually sits
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.slate900.withValues(alpha: 0.35),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.55],
                          ),
                        ),
                      ),

                      // Level badge (CEFR + localized difficulty, e.g. "A1 · Người mới")
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: levelColor.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.slate900.withValues(
                                    alpha: 0.22,
                                  ),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              courseLevelBadgeLabel(course.level),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppColors.surfaceLight,
                                    fontWeight: FontWeight.w700,
                                    fontSize: compact ? 10 : 10.5,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(contentPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      course.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const Spacer(),

                    // Stats row with explicit unit ("20 bài học" + XP or progress)
                    Row(
                      children: [
                        Flexible(
                          child: _buildStatChip(
                            context,
                            icon: Icons.menu_book_rounded,
                            value: 'course.totalLessonsCount'.tr(
                              namedArgs: {'count': '${course.totalLessons}'},
                            ),
                            color: AppColorRoles.primary(isDark),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (course.isEnrolled == true)
                          _buildProgressChip(context, course.userProgress ?? 0)
                        else if (course.totalXp > 0)
                          _buildStatChip(
                            context,
                            icon: Icons.bolt_rounded,
                            value: '${course.totalXp} XP',
                            color: AppColors.warningDark,
                          ),
                      ],
                    ),

                    // Progress indicator when enrolled
                    if (course.isEnrolled == true) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ((course.userProgress ?? 0) / 100).clamp(
                            0.0,
                            1.0,
                          ),
                          backgroundColor: isDark
                              ? AppColors.grey700
                              : AppColors.grey200,
                          minHeight: 4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getProgressColor(
                              course.userProgress ?? 0,
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseThumbnail(BuildContext context) {
    final primaryUrl = course.thumbnailUrl?.trim();
    final fallbackUrl = _fallbackUrl;
    final hash = course.id.hashCode;
    final gradientColors = _getGradientFromHash(hash);
    Widget gradientLoading() => Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
    );

    Widget finalFallback(BuildContext ctx) => Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.school,
            size: 32,
            color: Theme.of(ctx).colorScheme.surface,
          ),
        ),
      ),
    );

    Widget networkThumbnail(String url, {required Widget Function() onError}) =>
        CourseNetworkImage(
          url: url,
          placeholder: gradientLoading(),
          onError: onError,
        );

    // DB thumbnail exists: try it first, fall back to computed URL on error
    if (primaryUrl != null && primaryUrl.isNotEmpty) {
      return networkThumbnail(
        primaryUrl,
        onError: () => networkThumbnail(
          fallbackUrl,
          onError: () => finalFallback(context),
        ),
      );
    }

    return networkThumbnail(fallbackUrl, onError: () => finalFallback(context));
  }

  List<Color> _getGradientFromHash(int hash) {
    final gradients = _courseCardGradients;
    return gradients[hash.abs() % gradients.length];
  }

  Color _getProgressColor(double progress, {bool isDark = false}) {
    if (progress >= 80) return AppColors.greenSuccessBright;
    if (progress >= 50) return AppColors.orange;
    return AppColorRoles.primary(isDark);
  }

  Widget _buildStatChip(
    BuildContext context, {
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: compact ? 10 : 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressChip(BuildContext context, double progress) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: _getProgressColor(
          progress,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.trending_up,
            size: 12,
            color: _getProgressColor(
              progress,
              isDark: Theme.of(context).brightness == Brightness.dark,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${progress.toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: _getProgressColor(
                progress,
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filter Sheet Widget
class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _language;
  late String? _level;
  late String? _categorySlug;
  late bool _enrolledOnly;
  late String _sortOrder;

  static const List<(String?, Color)> _levels = [
    (null, AppColors.grey500),
    ('A1', AppColors.cefrA),
    ('A2', AppColors.teal),
    ('B1', AppColors.orange),
    ('B2', AppColors.deepOrange),
    ('C1', AppColors.cefrC),
    ('C2', AppColors.errorBright),
  ];

  static const _sortOptions = [
    ('course.sort.default', 'default', Icons.sort),
    ('course.sort.lessons', 'lessons', Icons.book_outlined),
    ('course.sort.xp', 'xp', Icons.star_outline),
    ('course.sort.az', 'az', Icons.sort_by_alpha),
  ];

  @override
  void initState() {
    super.initState();
    final p = context.read<CourseProvider>();
    _language = p.selectedLanguage;
    _level = p.selectedLevel;
    _categorySlug = p.selectedCategorySlug;
    _enrolledOnly = p.showEnrolledOnly;
    _sortOrder = p.sortOrder;
  }

  bool get _hasAnyFilter =>
      _language != null ||
      _level != null ||
      _categorySlug != null ||
      _enrolledOnly ||
      _sortOrder != 'default';

  Future<void> _applyFilters() async {
    final provider = context.read<CourseProvider>();
    final serverParamsChanged =
        _language != provider.selectedLanguage ||
        _level != provider.selectedLevel;

    // Apply client-side filters first (instant)
    provider.setClientFilters(
      categorySlug: _categorySlug,
      clearCategory: _categorySlug == null,
      enrolledOnly: _enrolledOnly,
      sortOrder: _sortOrder,
    );

    if (serverParamsChanged) {
      await provider.loadCourses(page: 1, language: _language, level: _level);
    }

    if (mounted) Navigator.pop(context);
  }

  void _clearAll() {
    setState(() {
      _language = null;
      _level = null;
      _categorySlug = null;
      _enrolledOnly = false;
      _sortOrder = 'default';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryAccent = AppColorRoles.primary(isDark);
    final categories = provider.categories;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: Column(
            children: [
              // Handle + header (fixed)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, AppSpacing.md, 20, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.grey300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryAccent,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            color: Theme.of(context).colorScheme.surface,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'course.filterCourses'.tr(),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        if (_hasAnyFilter)
                          TextButton(
                            onPressed: _clearAll,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.errorBright,
                            ),
                            child: Text('common.clear'.tr()),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Scrollable filter sections
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, AppSpacing.lg, 20, 16),
                  children: [
                    // ── Language ──────────────────────────────────────
                    _SectionHeader(label: 'common.language'.tr()),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(
                          label: 'course.langAll'.tr(),
                          isSelected: _language == null,
                          color: AppColors.grey500,
                          onTap: () => setState(() => _language = null),
                        ),
                        _Chip(
                          label: 'course.langEnglish'.tr(),
                          isSelected:
                              _language == 'en' || _language == 'English',
                          color: primaryAccent,
                          prefix: _LangBadge(
                            'EN',
                            primaryAccent,
                            _language == 'en' || _language == 'English',
                          ),
                          onTap: () => setState(() => _language = 'en'),
                        ),
                        _Chip(
                          label: 'course.langSpanish'.tr(),
                          isSelected:
                              _language == 'es' || _language == 'Spanish',
                          color: AppColors.orange,
                          prefix: _LangBadge(
                            'ES',
                            AppColors.orange,
                            _language == 'es' || _language == 'Spanish',
                          ),
                          onTap: () => setState(() => _language = 'es'),
                        ),
                        _Chip(
                          label: 'course.langVietnamese'.tr(),
                          isSelected:
                              _language == 'vi' || _language == 'Vietnamese',
                          color: AppColors.errorBright,
                          prefix: _LangBadge(
                            'VI',
                            AppColors.errorBright,
                            _language == 'vi' || _language == 'Vietnamese',
                          ),
                          onTap: () => setState(() => _language = 'vi'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Level ─────────────────────────────────────────
                    _SectionHeader(label: 'common.level'.tr()),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _levels
                          .map(
                            (e) => _Chip(
                              label: e.$1 == null
                                  ? 'course.langAll'.tr()
                                  : courseLevelBadgeLabel(e.$1!),
                              isSelected: _level?.toUpperCase() == e.$1,
                              color: e.$2,
                              onTap: () => setState(() => _level = e.$1),
                            ),
                          )
                          .toList(),
                    ),

                    // ── Category ──────────────────────────────────────
                    if (categories.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _SectionHeader(label: 'topics.category'.tr()),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Chip(
                            label: 'course.langAll'.tr(),
                            isSelected: _categorySlug == null,
                            color: AppColors.grey500,
                            onTap: () => setState(() => _categorySlug = null),
                          ),
                          ...categories.map(
                            (cat) => _Chip(
                              label: courseCategoryTitle(cat),
                              isSelected: _categorySlug == cat.slug,
                              color: courseCategoryColor(
                                colorHex: cat.color,
                                slugOrName: cat.slug,
                                isDark: isDark,
                              ),
                              onTap: () => setState(
                                () => _categorySlug = _categorySlug == cat.slug
                                    ? null
                                    : cat.slug,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ── Enrolled ──────────────────────────────────────
                    _SectionHeader(label: 'course.myEnrollments'.tr()),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _enrolledOnly = !_enrolledOnly),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: _enrolledOnly
                              ? AppColors.warningDark.withValues(alpha: 0.12)
                              : AppColors.grey500.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.school,
                              size: 18,
                              color: _enrolledOnly
                                  ? AppColors.warningDark
                                  : AppColors.grey500,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'course.showEnrolledOnly'.tr(),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,

                                      color: _enrolledOnly
                                          ? AppColors.warningDark
                                          : (isDark
                                                ? AppColors.textOnDarkSecondary
                                                : AppColors.textDark),
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            Switch.adaptive(
                              value: _enrolledOnly,
                              onChanged: (v) =>
                                  setState(() => _enrolledOnly = v),
                              activeThumbColor: AppColors.warningDark,
                              activeTrackColor: AppColors.warningDark
                                  .withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Sort By ───────────────────────────────────────
                    _SectionHeader(label: 'course.sortBy'.tr()),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sortOptions
                          .map(
                            (s) => _Chip(
                              label: s.$1.tr(),
                              isSelected: _sortOrder == s.$2,
                              color: AppColors.primary,
                              prefix: Icon(
                                s.$3,
                                size: 14,
                                color: _sortOrder == s.$2
                                    ? AppColors.textInverted
                                    : AppColors.primary,
                              ),
                              onTap: () => setState(() => _sortOrder = s.$2),
                            ),
                          )
                          .toList(),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),

              // Apply button (fixed at bottom)
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  AppSpacing.md,
                  20,
                  12 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? AppColors.borderDarkSoft
                          : AppColors.grey300,
                    ),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _applyFilters,
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.mdAll,
                      ),
                    ),
                    child: Text(
                      'course.applyFilters'.tr(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact section header row used inside _FilterSheet
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

/// Animated filter chip used inside _FilterSheet
class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final Widget? prefix;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.isSelected,
    required this.color,
    this.prefix,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TapTarget(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [color, color.withValues(alpha: 0.8)])
              : null,
          color: isSelected ? null : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prefix != null) ...[prefix!, const SizedBox(width: 6)],
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isSelected ? AppColors.textInverted : color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check,
                size: 14,
                color: Theme.of(context).colorScheme.surface,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Language badge prefix (e.g. "EN", "ES") inside a chip
class _LangBadge extends StatelessWidget {
  final String code;
  final Color color;
  final bool isSelected;

  const _LangBadge(this.code, this.color, this.isSelected);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.textInverted.withValues(alpha: 0.2)
            : color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: isSelected ? AppColors.textInverted : color,
        ),
      ),
    );
  }
}
