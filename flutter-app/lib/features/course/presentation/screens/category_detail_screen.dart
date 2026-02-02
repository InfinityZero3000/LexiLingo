import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';

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

  const CategoryDetailScreen({
    Key? key,
    required this.categoryId,
  }) : super(key: key);

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
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case CourseSortOption.level:
        sorted.sort((a, b) => _levelOrder(a.level).compareTo(_levelOrder(b.level)));
        break;
    }
    return sorted;
  }

  int _levelOrder(String level) {
    switch (level.toLowerCase()) {
      case 'beginner': return 0;
      case 'elementary': return 1;
      case 'intermediate': return 2;
      case 'advanced': return 3;
      case 'expert': return 4;
      default: return 5;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    category.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
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
                        color: Colors.white.withValues(alpha: 0.3),
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ),
                      // Sort dropdown
                      PopupMenuButton<CourseSortOption>(
                        icon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_sortOption.icon, size: 18, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
                          ],
                        ),
                        onSelected: (option) {
                          setState(() => _sortOption = option);
                        },
                        itemBuilder: (context) => CourseSortOption.values.map((option) {
                          return PopupMenuItem(
                            value: option,
                            child: Row(
                              children: [
                                Icon(option.icon, size: 18),
                                const SizedBox(width: 8),
                                Text(option.label),
                                if (option == _sortOption) ...[
                                  const Spacer(),
                                  const Icon(Icons.check, size: 18, color: Colors.green),
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
                          color: Colors.grey[600],
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
                    onRetry: () => provider.loadCoursesByCategory(widget.categoryId),
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
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No courses in this category yet',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.grey[600],
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
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final course = courses[index];
            return AnimatedListItem(
              index: index,
              duration: const Duration(milliseconds: 300),
              delayPerItem: const Duration(milliseconds: 50),
              child: _CourseCard(
                course: course,
                onTap: () => _navigateToCourseDetail(context, course.id),
              ),
            );
          },
          childCount: courses.length,
        ),
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
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final course = courses[index];
            return AnimatedListItem(
              index: index,
              duration: const Duration(milliseconds: 300),
              delayPerItem: const Duration(milliseconds: 50),
              child: _CourseGridCard(
                course: course,
                onTap: () => _navigateToCourseDetail(context, course.id),
              ),
            );
          },
          childCount: courses.length,
        ),
      ),
    );
  }

  void _navigateToCourseDetail(BuildContext context, String courseId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourseDetailScreen(courseId: courseId),
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
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }
}

/// Course Card Widget for grid view
class _CourseCard extends StatelessWidget {
  final CourseEntity course;
  final VoidCallback onTap;

  const _CourseCard({
    Key? key,
    required this.course,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
                  child: course.thumbnailUrl != null
                      ? Image.network(
                          course.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildPlaceholderImage();
                          },
                        )
                      : _buildPlaceholderImage(),
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
                              color: Colors.grey[600],
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
                        color: _getLevelColor(course.level).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        course.level,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _getLevelColor(course.level),
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
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        Icons.book,
        size: 40,
        color: Colors.grey[400],
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'beginner':
      case 'a1':
      case 'a2':
        return Colors.green;
      case 'intermediate':
      case 'b1':
      case 'b2':
        return Colors.orange;
      case 'advanced':
      case 'c1':
      case 'c2':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
}

/// Compact Course Card Widget for grid view
class _CourseGridCard extends StatelessWidget {
  final CourseEntity course;
  final VoidCallback onTap;

  const _CourseGridCard({
    Key? key,
    required this.course,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: SizedBox(
                  width: double.infinity,
                  child: course.thumbnailUrl != null
                      ? Image.network(
                          course.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                        )
                      : _buildPlaceholderImage(),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getLevelColor(course.level).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        course.level,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _getLevelColor(course.level),
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

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.book,
          size: 40,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'beginner':
      case 'a1':
      case 'a2':
        return Colors.green;
      case 'intermediate':
      case 'b1':
      case 'b2':
        return Colors.orange;
      case 'advanced':
      case 'c1':
      case 'c2':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
}
