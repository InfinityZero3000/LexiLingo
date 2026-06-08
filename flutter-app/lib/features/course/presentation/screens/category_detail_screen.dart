import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Sort options for courses
enum CourseSortOption {
  newest('Newest First', Icons.access_time),
  popular('Most Popular', Icons.trending_up),
  alphabetical('A-Z', Icons.sort_by_alpha),
  level('By Level', Icons.signal_cellular_alt);

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
          (a, b) => _levelOrder(a.level).compareTo(_levelOrder(b.level)),
        );
        break;
    }
    return sorted;
  }

  int _levelOrder(String level) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return 0;
      case 'elementary':
        return 1;
      case 'intermediate':
        return 2;
      case 'advanced':
        return 3;
      case 'expert':
        return 4;
      default:
        return 5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Consumer<CourseProvider>(
        builder: (context, provider, child) {
          // Find the category
          final category = provider.categories.firstWhere(
            (cat) => cat.id == widget.categoryId,
            orElse: () => provider.categories.first,
          );

          final categoryColor = _parseCategoryColor(category.color);
          final categoryIcon = _parseCategoryIcon(category.icon ?? 'book');

          // Use the courses loaded for this category
          final categoryCourses = provider.courses;

          return CustomScrollView(
            slivers: [
              // App Bar with category info
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: categoryColor,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    category.name,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.surface,
                      fontWeight: FontWeight.bold,
                      shadows: [
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
                          '${categoryCourses.length} ${categoryCourses.length == 1 ? 'course' : 'courses'} available',
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
                                    Text(option.label),
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
                        tooltip: _isGridView ? 'List view' : 'Grid view',
                      ),
                    ],
                  ),
                ),
              ),

              // Course list
              if (provider.isLoadingCourses && categoryCourses.isEmpty)
                SliverFillRemaining(
                  child: SkeletonList(
                    itemCount: 5,
                    padding: const EdgeInsets.all(16),
                  ),
                )
              else if (provider.coursesError != null && categoryCourses.isEmpty)
                SliverFillRemaining(
                  child: ErrorDisplayWidget.fromMessage(
                    message: provider.coursesError!,
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
          );
        },
      ),
    );
  }

  /// Build list view of courses
  Widget _buildCourseList(List<CourseEntity> courses) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
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

  Color _parseCategoryColor(String? colorHex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (colorHex == null || colorHex.isEmpty) {
      return AppColorRoles.primary(isDark);
    }
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
    } catch (e) {
      return AppColorRoles.primary(isDark);
    }
  }
}

String _courseImageUrl(CourseEntity course) {
  if (course.thumbnailUrl != null) return course.thumbnailUrl!;
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
    'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800&q=80', // financial charts
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
    'https://images.unsplash.com/photo-1546410531-bb4caa6b424d?w=800&q=80', // open book pages
    'https://images.unsplash.com/photo-1499750310107-5fef28a66643?w=800&q=80', // laptop on desk
    'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=800&q=80', // coffee on book
  ];
  const advanced = [
    'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&q=80', // library hall
    'https://images.unsplash.com/photo-1588072432836-e10032774350?w=800&q=80', // exam paper
    'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800&q=80', // office buildings
  ];

  if (tags.contains('ielts') ||
      tags.contains('test-prep') ||
      tags.contains('exam')) {
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Image.network(
                    _courseImageUrl(course),
                    fit: BoxFit.cover,
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

                    // Level badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getLevelColor(
                          course.level,
                          isDark,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        course.level,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _getLevelColor(course.level, isDark),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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

  Color _getLevelColor(String level, bool isDark) {
    switch (level.toLowerCase()) {
      case 'beginner':
      case 'a1':
      case 'a2':
        return AppColors.greenSuccessBright;
      case 'intermediate':
      case 'b1':
      case 'b2':
        return AppColors.orange;
      case 'advanced':
      case 'c1':
      case 'c2':
        return AppColors.errorBright;
      default:
        return AppColorRoles.primary(isDark);
    }
  }
}

/// Compact Course Card Widget for grid view
class _CourseGridCard extends StatelessWidget {
  final CourseEntity course;
  final VoidCallback onTap;

  const _CourseGridCard({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Image.network(
                    _courseImageUrl(course),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _buildPlaceholderImage(context),
                  ),
                ),
              ),
            ),
            // Content
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
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
                    const Spacer(),
                    // Level badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getLevelColor(
                          course.level,
                          isDark,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        course.level,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _getLevelColor(course.level, isDark),
                          fontWeight: FontWeight.bold,
                        ),
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

  Color _getLevelColor(String level, bool isDark) {
    switch (level.toLowerCase()) {
      case 'beginner':
      case 'a1':
      case 'a2':
        return AppColors.greenSuccessBright;
      case 'intermediate':
      case 'b1':
      case 'b2':
        return AppColors.orange;
      case 'advanced':
      case 'c1':
      case 'c2':
        return AppColors.errorBright;
      default:
        return AppColorRoles.primary(isDark);
    }
  }
}
