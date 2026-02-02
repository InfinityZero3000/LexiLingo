import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/presentation/screens/category_detail_screen.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';

/// Course List Screen
/// Displays courses in horizontal scrolling sections grouped by category
class CourseListScreen extends StatefulWidget {
  const CourseListScreen({Key? key}) : super(key: key);

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
    return Scaffold(
      body: Consumer<CourseProvider>(
        builder: (context, provider, child) {
          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Modern SliverAppBar with gradient
              SliverAppBar(
                expandedHeight: 120,
                floating: true,
                pinned: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF6366F1).withValues(alpha: 0.1),
                          const Color(0xFF8B5CF6).withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 40),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.explore, color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Discover Courses',
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${provider.courses.length} courses available',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[600],
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
                ),
                actions: [
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.tune_rounded, color: Color(0xFF6366F1)),
                      onPressed: () => _showFilterSheet(context),
                      tooltip: 'Filter',
                    ),
                  ),
                ],
              ),

              // Content
              if ((provider.isLoadingCourses || provider.isLoadingCategories) && 
                  provider.courses.isEmpty && 
                  provider.categories.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.coursesError != null && provider.courses.isEmpty)
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
                  child: EmptyStateWidget.courses(
                    onExplore: () {
                      provider.refreshCourses();
                      provider.loadCategories();
                    },
                  ),
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
    final categories = provider.categories;
    final shouldUseCategories = categories.isNotEmpty;
    final sections = shouldUseCategories 
        ? categories 
        : provider.coursesByCategory.keys.toList();

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == sections.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (shouldUseCategories) {
            final category = categories[index];
            final categoryCourses = provider.courses;
            
            if (categoryCourses.isEmpty) {
              return const SizedBox.shrink();
            }

            return _CategorySection(
              categoryId: category.id,
              title: category.name,
              description: '${categoryCourses.length} ${categoryCourses.length == 1 ? 'course' : 'courses'}',
              icon: _parseCategoryIcon(category.icon ?? 'book'),
              color: _parseCategoryColor(category.color),
              courses: categoryCourses,
              onCourseTap: (courseId) =>
                  _navigateToCourseDetail(context, courseId),
              onSeeAll: () => _navigateToCategoryDetail(context, category.id),
            );
          } else {
            final groupedCourses = provider.coursesByCategory;
            final levelKey = sections[index] as String;
            final courses = groupedCourses[levelKey]!;

            return _CategorySection(
              categoryId: levelKey,
              title: levelKey,
              description: '${courses.length} ${courses.length == 1 ? 'course' : 'courses'}',
              icon: _getLevelIcon(levelKey),
              color: _getLevelColor(levelKey),
              courses: courses,
              onCourseTap: (courseId) =>
                  _navigateToCourseDetail(context, courseId),
              onSeeAll: null,
            );
          }
        },
        childCount: sections.length + (provider.isLoadingCourses ? 1 : 0),
      ),
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

  Color _parseCategoryColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) {
      return Colors.blue;
    }
    try {
      // Remove # if present
      final hex = colorHex.replaceAll('#', '');
      // Parse hex color (supports both RGB and ARGB)
      return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
    } catch (e) {
      return Colors.blue;
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

  Color _getLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return Colors.green;
      case 'intermediate':
        return Colors.orange;
      case 'advanced':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _FilterSheet(),
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
    Key? key,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.courses,
    required this.onCourseTap,
    this.onSeeAll,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
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
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: const Text('See All'),
                ),
            ],
          ),
        ),

        // Horizontal Course List with staggered animation
        SizedBox(
          height: 280,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];
              return AnimatedListItem(
                index: index,
                duration: const Duration(milliseconds: 300),
                delayPerItem: const Duration(milliseconds: 80),
                child: _HorizontalCourseCard(
                  course: course,
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
  final VoidCallback onTap;

  const _HorizontalCourseCard({
    Key? key,
    required this.course,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: 200,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Card(
        elevation: 4,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Enhanced Hero Thumbnail with gradient overlay
              Hero(
                tag: 'discovery-course-image-${course.id}',
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background image or placeholder
                        course.thumbnailUrl != null
                            ? Image.network(
                                course.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildHeroPlaceholder(context);
                                },
                              )
                            : _buildHeroPlaceholder(context),
                        
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
                              color: _getLevelColor(course.level).withValues(alpha: 0.9),
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
                              style: const TextStyle(
                                color: Colors.white,
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
                                const Icon(
                                  Icons.star,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${course.totalXp}',
                                  style: const TextStyle(
                                    color: Colors.white,
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
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        course.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 6),

                      // Language chip with flag
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getLanguageCode(course.language),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              course.language,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Stats row with icons
                      Row(
                        children: [
                          _buildStatChip(
                            icon: Icons.book_outlined,
                            value: '${course.totalLessons}',
                            color: Colors.blue,
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
                      const SizedBox(height: 4),
                      if (course.isEnrolled == true) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (course.userProgress ?? 0) / 100,
                            backgroundColor: isDark 
                                ? Colors.grey[700] 
                                : Colors.grey[200],
                            minHeight: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getProgressColor(course.userProgress ?? 0),
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'Start',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
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

  Widget _buildHeroPlaceholder(BuildContext context) {
    // Generate a unique gradient based on course ID
    final hash = course.id.hashCode;
    final gradientColors = _getGradientFromHash(hash);
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -10,
            left: -10,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          // Icon in center
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getLanguageIcon(course.language),
                size: 32,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _getGradientFromHash(int hash) {
    final gradients = [
      [const Color(0xFF667eea), const Color(0xFF764ba2)], // Purple
      [const Color(0xFFf093fb), const Color(0xFFf5576c)], // Pink
      [const Color(0xFF4facfe), const Color(0xFF00f2fe)], // Blue
      [const Color(0xFF43e97b), const Color(0xFF38f9d7)], // Green
      [const Color(0xFFfa709a), const Color(0xFFfee140)], // Sunset
      [const Color(0xFF30cfd0), const Color(0xFF330867)], // Ocean
      [const Color(0xFFa8edea), const Color(0xFFfed6e3)], // Pastel
      [const Color(0xFFff9a9e), const Color(0xFFfecfef)], // Rose
    ];
    return gradients[hash.abs() % gradients.length];
  }

  IconData _getLanguageIcon(String language) {
    switch (language.toLowerCase()) {
      case 'english':
        return Icons.language;
      case 'spanish':
        return Icons.music_note;
      case 'french':
        return Icons.wine_bar;
      case 'german':
        return Icons.engineering;
      case 'japanese':
        return Icons.temple_buddhist;
      case 'chinese':
        return Icons.temple_hindu;
      case 'korean':
        return Icons.movie;
      default:
        return Icons.school;
    }
  }

  String _getLanguageCode(String language) {
    switch (language.toLowerCase()) {
      case 'english':
        return 'EN';
      case 'spanish':
        return 'ES';
      case 'french':
        return 'FR';
      case 'german':
        return 'DE';
      case 'japanese':
        return 'JP';
      case 'chinese':
        return 'CN';
      case 'korean':
        return 'KR';
      case 'vietnamese':
        return 'VN';
      default:
        return 'INT';
    }
  }

  Color _getLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return Colors.green;
      case 'elementary':
        return Colors.lightGreen;
      case 'intermediate':
        return Colors.orange;
      case 'upper-intermediate':
        return Colors.deepOrange;
      case 'advanced':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Color _getProgressColor(double progress) {
    if (progress >= 80) return Colors.green;
    if (progress >= 50) return Colors.orange;
    return Colors.blue;
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
        color: _getProgressColor(progress).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.trending_up,
            size: 12,
            color: _getProgressColor(progress),
          ),
          const SizedBox(width: 4),
          Text(
            '${progress.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _getProgressColor(progress),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filter Sheet Widget
class _FilterSheet extends StatelessWidget {
  const _FilterSheet({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseProvider>();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
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
          const SizedBox(height: 20),
          
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Filter Courses',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (provider.selectedLanguage != null || provider.selectedLevel != null)
                TextButton.icon(
                  onPressed: () {
                    provider.clearFilters();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[400],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Language Filter
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.language, size: 16, color: Colors.blue),
              ),
              const SizedBox(width: 8),
              const Text('Language', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip(
                context: context,
                label: 'All',
                isSelected: provider.selectedLanguage == null,
                color: Colors.grey,
                onTap: () {
                  provider.filterByLanguage(null);
                  Navigator.pop(context);
                },
              ),
              _buildFilterChip(
                context: context,
                label: 'English',
                isSelected: provider.selectedLanguage == 'English',
                color: Colors.blue,
                iconWidget: _buildLanguageIcon('EN', Colors.blue, provider.selectedLanguage == 'English'),
                onTap: () {
                  provider.filterByLanguage('English');
                  Navigator.pop(context);
                },
              ),
              _buildFilterChip(
                context: context,
                label: 'Spanish',
                isSelected: provider.selectedLanguage == 'Spanish',
                color: Colors.orange,
                iconWidget: _buildLanguageIcon('ES', Colors.orange, provider.selectedLanguage == 'Spanish'),
                onTap: () {
                  provider.filterByLanguage('Spanish');
                  Navigator.pop(context);
                },
              ),
              _buildFilterChip(
                context: context,
                label: 'Vietnamese',
                isSelected: provider.selectedLanguage == 'Vietnamese',
                color: Colors.red,
                iconWidget: _buildLanguageIcon('VI', Colors.red, provider.selectedLanguage == 'Vietnamese'),
                onTap: () {
                  provider.filterByLanguage('Vietnamese');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Level Filter
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.signal_cellular_alt, size: 16, color: Colors.purple),
              ),
              const SizedBox(width: 8),
              const Text('Level', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip(
                context: context,
                label: 'All',
                isSelected: provider.selectedLevel == null,
                color: Colors.grey,
                onTap: () {
                  provider.filterByLevel(null);
                  Navigator.pop(context);
                },
              ),
              _buildFilterChip(
                context: context,
                label: 'Beginner',
                isSelected: provider.selectedLevel == 'Beginner',
                color: Colors.green,
                onTap: () {
                  provider.filterByLevel('Beginner');
                  Navigator.pop(context);
                },
              ),
              _buildFilterChip(
                context: context,
                label: 'Intermediate',
                isSelected: provider.selectedLevel == 'Intermediate',
                color: Colors.orange,
                onTap: () {
                  provider.filterByLevel('Intermediate');
                  Navigator.pop(context);
                },
              ),
              _buildFilterChip(
                context: context,
                label: 'Advanced',
                isSelected: provider.selectedLevel == 'Advanced',
                color: Colors.red,
                onTap: () {
                  provider.filterByLevel('Advanced');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required Color color,
    Widget? iconWidget,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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
            if (iconWidget != null) ...[
              iconWidget,
              const SizedBox(width: 6),
            ],
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
              const Icon(Icons.check, size: 14, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageIcon(String code, Color color, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.2) : color.withValues(alpha: 0.2),
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
