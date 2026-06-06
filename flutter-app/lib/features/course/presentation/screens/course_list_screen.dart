import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/presentation/screens/category_detail_screen.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_category_entity.dart';

/// Course List Screen
/// Displays courses in horizontal scrolling sections grouped by category
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
          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Modern SliverAppBar with gradient
              SliverAppBar(
                expandedHeight: 100,
                floating: true,
                pinned: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  background: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: primaryAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.explore,
                                  color: Theme.of(context).colorScheme.surface,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'course.discoverCourses'.tr(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${provider.courses.length} courses available',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: provider.hasActiveFilters
                                          ? primaryAccent
                                          : primaryAccent.withValues(
                                              alpha: 0.14),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.tune_rounded,
                                        color: provider.hasActiveFilters
                                            ? Colors.white
                                            : primaryAccent,
                                      ),
                                      onPressed: () =>
                                          _showFilterSheet(context),
                                      tooltip: 'Filter',
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
                                          color: Colors.amber,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .scaffoldBackgroundColor,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: const [],
              ),

              // Hero banner below heading
              const SliverToBoxAdapter(child: _CourseBanner()),

              // Content
              if ((provider.isLoadingCourses || provider.isLoadingCategories) &&
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
              else if (provider.courses.isEmpty)
                SliverFillRemaining(
                  child: EmptyStateWidget.courses(),
                )
              else
                _buildCourseContent(context, provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCourseContent(BuildContext context, CourseProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayCourses = provider.filteredCourses;

    // Show empty-filtered state when client-side filters result in nothing
    if (displayCourses.isEmpty) {
      return SliverFillRemaining(
        child: EmptyStateWidget.searchResults(),
      );
    }

    final categories = provider.categories;
    final nonEmptyCategorySections =
        <MapEntry<CourseCategoryEntity, List<CourseEntity>>>[];
    final mappedCourseIds = <String>{};

    for (final category in categories) {
      final categoryCourses = displayCourses
          .where(
            (c) =>
                c.tags.contains(category.slug) ||
                c.tags.contains(category.name.toLowerCase()) ||
                (c.tags.isEmpty && category.slug == 'general'),
          )
          .toList();

      if (categoryCourses.isNotEmpty) {
        nonEmptyCategorySections.add(MapEntry(category, categoryCourses));
        for (final course in categoryCourses) {
          mappedCourseIds.add(course.id);
        }
      }
    }

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
      // Flat grouped-by-level list
      final grouped = <String, List<CourseEntity>>{};
      for (final course in displayCourses) {
        grouped.putIfAbsent(course.level, () => []).add(course);
      }
      final levelKeys = grouped.keys.toList();

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
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
              title: levelKey,
              description:
                  '${courses.length} ${courses.length == 1 ? 'course' : 'courses'}',
              icon: _getLevelIcon(levelKey),
              color: _getLevelColor(levelKey, isDark: isDark),
              courses: courses,
              onCourseTap: (courseId) =>
                  _navigateToCourseDetail(context, courseId),
              onSeeAll: null,
            );
          },
          childCount: levelKeys.length + (provider.isLoadingCourses ? 1 : 0),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
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
          title: category.name,
          description:
              '${categoryCourses.length} ${categoryCourses.length == 1 ? 'course' : 'courses'}',
          icon: _parseCategoryIcon(category.icon ?? 'book'),
          color: _parseCategoryColor(category.color, isDark: isDark),
          courses: categoryCourses,
          onCourseTap: (courseId) =>
              _navigateToCourseDetail(context, courseId),
          onSeeAll: () => _navigateToCategoryDetail(context, category.id),
        );
      }, childCount: nonEmptyCategorySections.length + (provider.isLoadingCourses ? 1 : 0)),
    );
  }

  void _navigateToCourseDetail(BuildContext context, String courseId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourseDetailScreen(
          courseId: courseId,
          heroTag: 'discovery-course-image-$courseId',
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

  IconData _parseCategoryIcon(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'school':
        return Icons.school;
      case 'menu_book':
        return Icons.menu_book;
      case 'work':
        return Icons.work;
      case 'chat':
        return Icons.chat;
      case 'flight':
        return Icons.flight;
      case 'psychology':
        return Icons.psychology;
      case 'star':
        return Icons.star;
      case 'category':
        return Icons.category;
      default:
        return Icons.book;
    }
  }

  Color _parseCategoryColor(String? colorHex, {required bool isDark}) {
    if (colorHex == null || colorHex.isEmpty) {
      return AppColorRoles.primary(isDark);
    }
    try {
      // Remove # if present
      final hex = colorHex.replaceAll('#', '');
      // Parse hex color (supports both RGB and ARGB)
      return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
    } catch (e) {
      return AppColorRoles.primary(isDark);
    }
  }

  IconData _getLevelIcon(String level) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return Icons.school_outlined;
      case 'intermediate':
        return Icons.trending_up;
      case 'advanced':
        return Icons.emoji_events_outlined;
      default:
        return Icons.book_outlined;
    }
  }

  Color _getLevelColor(String level, {bool isDark = false}) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return AppColors.greenSuccess;
      case 'intermediate':
        return AppColors.primary; // blue — on-theme
      case 'advanced':
        return AppColors.purple; // violet — premium feel
      default:
        return AppColorRoles.primary(isDark);
    }
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Banner image
            Image.asset(
              'assets/course/banner_course.png',
              width: double.infinity,
              height: 130,
              fit: BoxFit.cover,
            ),
            // Subtle overlay so text is readable
            Container(
              height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    (isDark ? Colors.black : const Color(0xFF0D47A1))
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
                    'Start Learning',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pick a course & start your\nlanguage journey today!',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      height: 1.4,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.3),
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

/// Category Section Widget
/// Displays a category title with horizontally scrolling course cards
class _CategorySection extends StatelessWidget {
  final String categoryId;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<CourseEntity> courses;
  final Function(String courseId) onCourseTap;
  final VoidCallback? onSeeAll;

  const _CategorySection({
    required this.categoryId,
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
          padding: EdgeInsets.symmetric(
            horizontal: isCompactMobile ? 14 : 16,
            vertical: isCompactMobile ? 6 : 8,
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isCompactMobile ? 7 : 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: Text('common.seeAll'.tr()),
                ),
            ],
          ),
        ),

        // Horizontal Course List with staggered animation
        SizedBox(
          height: isCompactMobile ? 220 : 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: isCompactMobile ? 10 : 12,
            ),
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];
              return AnimatedListItem(
                index: index,
                duration: const Duration(milliseconds: 300),
                delayPerItem: const Duration(milliseconds: 80),
                child: _HorizontalCourseCard(
                  course: course,
                  compact: isCompactMobile,
                  onTap: () => onCourseTap(course.id),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

/// Horizontal Course Card Widget
/// Compact card design for horizontal scrolling with enhanced hero images
class _HorizontalCourseCard extends StatelessWidget {
  final CourseEntity course;
  final bool compact;
  final VoidCallback onTap;

  const _HorizontalCourseCard({
    required this.course,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardWidth = compact ? 150.0 : 170.0;
    final cardRadius = compact ? 14.0 : 16.0;
    final contentPadding = compact ? 10.0 : 12.0;
    final titleFontSize = compact ? 13.0 : 14.0;
    final imageAspectRatio = compact ? 16 / 9 : 16 / 10;
    final displayTags = _visibleCourseTags(course);

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Card(
        elevation: 4,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(cardRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Enhanced Hero Thumbnail with gradient overlay
              Hero(
                tag: 'discovery-course-image-${course.id}',
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

                        // Gradient overlay for better text visibility
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.5),
                              ],
                            ),
                          ),
                        ),

                        // Level badge
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getLevelColor(
                                course.level,
                                isDark: isDark,
                              ).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              course.level,
                              style: TextStyle(
                                color: AppColors.surfaceLight,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        // XP badge (bottom right)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  size: 12,
                                  color: AppColors.surfaceLight,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${course.totalXp}',
                                  style: TextStyle(
                                    color: AppColors.surfaceLight,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
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
                      // Tags row — horizontally scrollable, above title
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Language chip (INT + en)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.7),
                                    Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.5),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _getLanguageCode(course.language),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getLanguageLabel(course.language),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Learner-facing tags only. Internal seed/crawl
                            // metadata stays in data for filtering/imports.
                            ...displayTags.map(
                              (tag) => Padding(
                                padding: const EdgeInsets.only(left: 5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : AppColors.grey100,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white24
                                          : AppColors.grey300,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white70
                                          : AppColors.grey700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Title
                      Text(
                        course.title,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const Spacer(),

                      // Stats row with icons
                      Row(
                        children: [
                          _buildStatChip(
                            icon: Icons.book_outlined,
                            value: '${course.totalLessons}',
                            color: AppColorRoles.primary(isDark),
                          ),
                          const SizedBox(width: 8),
                          if (course.isEnrolled == true)
                            Expanded(
                              child: _buildProgressChip(
                                context,
                                course.userProgress ?? 0,
                              ),
                            ),
                        ],
                      ),

                      // Progress or Enroll indicator
                      if (course.isEnrolled == true) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (course.userProgress ?? 0) / 100,
                            backgroundColor: isDark
                                ? Colors.grey[700]
                                : Colors.grey[200],
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
      ),
    );
  }

  String _getCourseImageUrl() {
    final tags = course.tags.map((t) => t.toLowerCase()).toSet();
    final level = course.level.toLowerCase();
    final pick = course.id.hashCode.abs();

    const ielts = [
      'https://images.unsplash.com/photo-1588072432836-e10032774350?w=800&q=80', // exam pencil
      'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80', // notepad + ruler
      'https://images.unsplash.com/photo-1523050854058-8df90110c9f1?w=800&q=80', // graduation cap
    ];
    const business = [
      'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800&q=80', // glass office buildings
      'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800&q=80',    // financial charts
      'https://images.unsplash.com/photo-1486312338219-ce68d2c6f44d?w=800&q=80', // laptop workspace
    ];
    const conversation = [
      'https://images.unsplash.com/photo-1499750310107-5fef28a66643?w=800&q=80', // laptop at café
      'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=800&q=80', // coffee on book
      'https://images.unsplash.com/photo-1488590528505-98d2b5aba04b?w=800&q=80', // laptop keyboard
    ];
    const grammar = [
      'https://images.unsplash.com/photo-1471899236350-e3016bf1a395?w=800&q=80', // fountain pen
      'https://images.unsplash.com/photo-1432821596592-e2c18b78144f?w=800&q=80', // spiral notebook
      'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=800&q=80', // pen on paper
    ];
    const vocabulary = [
      'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=800&q=80', // colorful books
      'https://images.unsplash.com/photo-1476275466078-4007374efbbe?w=800&q=80', // stacked books
      'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=800&q=80', // desk with books
    ];
    const reading = [
      'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&q=80', // library hall
      'https://images.unsplash.com/photo-1524578271613-d550eacf6090?w=800&q=80', // stacked books
      'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=800&q=80', // open book
    ];
    const listening = [
      'https://images.unsplash.com/photo-1484704849700-f032a568e944?w=800&q=80', // headphones
      'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=800&q=80', // headphones 2
      'https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=800&q=80', // headphones 3
    ];
    const writing = [
      'https://images.unsplash.com/photo-1517842645767-c639042777db?w=800&q=80', // desk + notepad
      'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80', // notepad + ruler
      'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=800&q=80', // pen on paper
    ];
    const travel = [
      'https://images.unsplash.com/photo-1488085061387-422e29b40080?w=800&q=80', // world map
      'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=800&q=80', // open road
      'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=800&q=80', // mountain lake
    ];
    const beginner = [
      'https://images.unsplash.com/photo-1427504494785-3a9ca7044f45?w=800&q=80', // colored crayons
      'https://images.unsplash.com/photo-1506880018603-83d5b814b5a6?w=800&q=80', // colored pencils
      'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=800&q=80', // colorful books
    ];
    const intermediate = [
      'https://images.unsplash.com/photo-1546410531-bb4caa6b424d?w=800&q=80',    // open book pages
      'https://images.unsplash.com/photo-1499750310107-5fef28a66643?w=800&q=80', // laptop on desk
      'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=800&q=80', // coffee on book
    ];
    const advanced = [
      'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&q=80', // library hall
      'https://images.unsplash.com/photo-1588072432836-e10032774350?w=800&q=80', // exam paper
      'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800&q=80', // office buildings
    ];

    if (tags.contains('ielts') || tags.contains('test-prep') || tags.contains('exam')) {
      return ielts[pick % ielts.length];
    }
    if (tags.contains('business') || tags.contains('business-english')) {
      return business[pick % business.length];
    }
    if (tags.contains('conversation') || tags.contains('speaking')) {
      return conversation[pick % conversation.length];
    }
    if (tags.contains('grammar')) {
      return grammar[pick % grammar.length];
    }
    if (tags.contains('vocabulary') || tags.contains('vocab')) {
      return vocabulary[pick % vocabulary.length];
    }
    if (tags.contains('reading')) {
      return reading[pick % reading.length];
    }
    if (tags.contains('listening')) {
      return listening[pick % listening.length];
    }
    if (tags.contains('writing')) {
      return writing[pick % writing.length];
    }
    if (tags.contains('travel')) {
      return travel[pick % travel.length];
    }

    switch (level) {
      case 'beginner':
      case 'elementary':
        return beginner[pick % beginner.length];
      case 'intermediate':
      case 'upper-intermediate':
        return intermediate[pick % intermediate.length];
      case 'advanced':
        return advanced[pick % advanced.length];
      default:
        return reading[pick % reading.length];
    }
  }

  Widget _buildCourseThumbnail(BuildContext context) {
    final imageUrl = course.thumbnailUrl ?? _getCourseImageUrl();
    final hash = course.id.hashCode;
    final gradientColors = _getGradientFromHash(hash);

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
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
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.school,
                size: 32,
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        );
      },
    );
  }

  static const Set<String> _hiddenCourseTagKeys = {
    'seed',
    'seeded',
    'crawl',
    'crawled',
    'crawler',
    'source',
    'import',
    'imported',
    'generated',
    'auto',
    'automatic',
    'internal',
    'system',
    'demo',
    'sample',
    'kg',
    'tracecag',
    'trace_cag',
    'graphcag',
    'graph_cag',
  };

  List<String> _visibleCourseTags(CourseEntity course) {
    final hiddenKeys = {
      ..._hiddenCourseTagKeys,
      _normalizeTagKey(course.language),
      _normalizeTagKey(_getLanguageCode(course.language)),
      _normalizeTagKey(_getLanguageLabel(course.language)),
      _normalizeTagKey(course.level),
    };
    final seen = <String>{};
    final visible = <String>[];

    for (final tag in course.tags) {
      final key = _normalizeTagKey(tag);
      if (key.isEmpty) continue;
      if (hiddenKeys.contains(key)) continue;
      if (key.contains('crawl') || key.contains('seed')) continue;
      if (RegExp(r'^[abc][12]$').hasMatch(key)) continue;
      if (!seen.add(key)) continue;

      visible.add(_formatCourseTag(tag));
    }

    return visible;
  }

  String _normalizeTagKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _formatCourseTag(String tag) {
    final key = _normalizeTagKey(tag);
    const aliases = {
      'vocab': 'Vocabulary',
      'vocabulary': 'Vocabulary',
      'grammar': 'Grammar',
      'conversation': 'Conversation',
      'speaking': 'Speaking',
      'listening': 'Listening',
      'reading': 'Reading',
      'writing': 'Writing',
      'pronunciation': 'Pronunciation',
      'business': 'Business',
      'travel': 'Travel',
      'exam': 'Exam Prep',
    };
    final alias = aliases[key];
    if (alias != null) return alias;

    return key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  List<Color> _getGradientFromHash(int hash) {
    final gradients = [
      [AppColors.primary, AppColors.purple],
      [AppColors.purple, const Color(0xFFf5576c)],
      [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
      [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
      [const Color(0xFFfa709a), const Color(0xFFfee140)],
      [const Color(0xFF30cfd0), const Color(0xFF330867)],
      [const Color(0xFFa8edea), const Color(0xFFfed6e3)],
      [const Color(0xFFff9a9e), const Color(0xFFfecfef)],
    ];
    return gradients[hash.abs() % gradients.length];
  }

  String _getLanguageCode(String language) {
    switch (language.toLowerCase()) {
      case 'en':
      case 'en-us':
      case 'en_us':
      case 'english':
        return 'EN';
      case 'es':
      case 'spanish':
        return 'ES';
      case 'fr':
      case 'french':
        return 'FR';
      case 'de':
      case 'german':
        return 'DE';
      case 'ja':
      case 'jp':
      case 'japanese':
        return 'JP';
      case 'zh':
      case 'cn':
      case 'chinese':
        return 'CN';
      case 'ko':
      case 'kr':
      case 'korean':
        return 'KR';
      case 'vi':
      case 'vn':
      case 'vietnamese':
        return 'VN';
      default:
        return 'INT';
    }
  }

  String _getLanguageLabel(String language) {
    switch (language.toLowerCase()) {
      case 'en':
      case 'en-us':
      case 'en_us':
      case 'english':
        return 'English';
      case 'es':
      case 'spanish':
        return 'Spanish';
      case 'fr':
      case 'french':
        return 'French';
      case 'de':
      case 'german':
        return 'German';
      case 'ja':
      case 'jp':
      case 'japanese':
        return 'Japanese';
      case 'zh':
      case 'cn':
      case 'chinese':
        return 'Chinese';
      case 'ko':
      case 'kr':
      case 'korean':
        return 'Korean';
      case 'vi':
      case 'vn':
      case 'vietnamese':
        return 'Vietnamese';
      default:
        return language;
    }
  }

  Color _getLevelColor(String level, {bool isDark = false}) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return AppColors.greenSuccessBright;
      case 'elementary':
        return Colors.lightGreen;
      case 'intermediate':
        return AppColors.orange;
      case 'upper-intermediate':
        return AppColors.deepOrange;
      case 'advanced':
        return AppColors.errorBright;
      default:
        return AppColorRoles.primary(isDark);
    }
  }

  Color _getProgressColor(double progress, {bool isDark = false}) {
    if (progress >= 80) return AppColors.greenSuccessBright;
    if (progress >= 50) return AppColors.orange;
    return AppColorRoles.primary(isDark);
  }

  Widget _buildStatChip({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressChip(BuildContext context, double progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _getProgressColor(
          progress,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
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
            style: TextStyle(
              fontSize: 10,
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

  static const List<(String, String?, Color)> _levels = [
    ('All', null, Colors.grey),
    ('Beginner', 'Beginner', AppColors.greenSuccessBright),
    ('Elementary', 'Elementary', Colors.lightGreen),
    ('Pre-Intermediate', 'Pre-Intermediate', Colors.teal),
    ('Intermediate', 'Intermediate', AppColors.orange),
    ('Upper-Intermediate', 'Upper-Intermediate', AppColors.deepOrange),
    ('Advanced', 'Advanced', AppColors.errorBright),
  ];

  static const _sortOptions = [
    ('Default', 'default', Icons.sort),
    ('Most Lessons', 'lessons', Icons.book_outlined),
    ('Highest XP', 'xp', Icons.star_outline),
    ('A → Z', 'az', Icons.sort_by_alpha),
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
        _language != provider.selectedLanguage || _level != provider.selectedLevel;

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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle + header (fixed)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            color: Theme.of(context).colorScheme.surface,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'course.filterCourses'.tr(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_hasAnyFilter)
                          TextButton.icon(
                            onPressed: _clearAll,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: Text('common.clear'.tr()),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red[400]),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    // ── Language ──────────────────────────────────────
                    _SectionHeader(
                      icon: Icons.language,
                      color: primaryAccent,
                      label: 'common.language'.tr(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(
                          label: 'All',
                          isSelected: _language == null,
                          color: Colors.grey,
                          onTap: () => setState(() => _language = null),
                        ),
                        _Chip(
                          label: 'English',
                          isSelected: _language == 'English',
                          color: primaryAccent,
                          prefix: _LangBadge(
                              'EN', primaryAccent, _language == 'English'),
                          onTap: () => setState(() => _language = 'English'),
                        ),
                        _Chip(
                          label: 'Spanish',
                          isSelected: _language == 'Spanish',
                          color: AppColors.orange,
                          prefix: _LangBadge(
                              'ES', AppColors.orange, _language == 'Spanish'),
                          onTap: () => setState(() => _language = 'Spanish'),
                        ),
                        _Chip(
                          label: 'Vietnamese',
                          isSelected: _language == 'Vietnamese',
                          color: AppColors.errorBright,
                          prefix: _LangBadge('VI', AppColors.errorBright,
                              _language == 'Vietnamese'),
                          onTap: () =>
                              setState(() => _language = 'Vietnamese'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Level ─────────────────────────────────────────
                    _SectionHeader(
                      icon: Icons.signal_cellular_alt,
                      color: AppColors.purple,
                      label: 'common.level'.tr(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _levels
                          .map(
                            (e) => _Chip(
                              label: e.$1,
                              isSelected: _level == e.$2,
                              color: e.$3,
                              onTap: () => setState(() => _level = e.$2),
                            ),
                          )
                          .toList(),
                    ),

                    // ── Category ──────────────────────────────────────
                    if (categories.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _SectionHeader(
                        icon: Icons.category_outlined,
                        color: AppColors.teal,
                        label: 'Category',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Chip(
                            label: 'All',
                            isSelected: _categorySlug == null,
                            color: Colors.grey,
                            onTap: () => setState(() => _categorySlug = null),
                          ),
                          ...categories.map(
                            (cat) => _Chip(
                              label: cat.name,
                              isSelected: _categorySlug == cat.slug,
                              color: _parseCategoryColor(
                                  cat.color, isDark: isDark),
                              onTap: () => setState(
                                  () => _categorySlug = _categorySlug == cat.slug
                                      ? null
                                      : cat.slug),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ── Enrolled ──────────────────────────────────────
                    _SectionHeader(
                      icon: Icons.bookmark_outline,
                      color: Colors.amber[700]!,
                      label: 'My Enrollments',
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _enrolledOnly = !_enrolledOnly),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _enrolledOnly
                              ? Colors.amber[700]!.withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _enrolledOnly
                                ? Colors.amber[700]!
                                : Colors.grey.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.school,
                              size: 18,
                              color: _enrolledOnly
                                  ? Colors.amber[700]
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Show enrolled courses only',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: _enrolledOnly
                                    ? Colors.amber[700]
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                              ),
                            ),
                            const Spacer(),
                            Switch.adaptive(
                              value: _enrolledOnly,
                              onChanged: (v) =>
                                  setState(() => _enrolledOnly = v),
                              activeThumbColor: Colors.amber[700],
                              activeTrackColor:
                                  Colors.amber[700]!.withValues(alpha: 0.4),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Sort By ───────────────────────────────────────
                    _SectionHeader(
                      icon: Icons.sort,
                      color: AppColors.primary,
                      label: 'Sort By',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sortOptions
                          .map(
                            (s) => _Chip(
                              label: s.$1,
                              isSelected: _sortOrder == s.$2,
                              color: AppColors.primary,
                              prefix: Icon(
                                s.$3,
                                size: 14,
                                color: _sortOrder == s.$2
                                    ? Colors.white
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
                    20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12),
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
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Apply Filters',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
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

  Color _parseCategoryColor(String? colorHex, {required bool isDark}) {
    if (colorHex == null || colorHex.isEmpty) {
      return AppColorRoles.primary(isDark);
    }
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
    } catch (_) {
      return AppColorRoles.primary(isDark);
    }
  }
}

/// Compact section header row used inside _FilterSheet
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [color, color.withValues(alpha: 0.8)])
              : null,
          color: isSelected ? null : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 0 : 1,
          ),
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
              style: TextStyle(
                color: isSelected ? Colors.white : color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.2)
            : color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : color,
        ),
      ),
    );
  }
}
