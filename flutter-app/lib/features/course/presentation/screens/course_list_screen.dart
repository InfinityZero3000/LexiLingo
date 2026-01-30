import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
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
    
    // Load initial courses
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CourseProvider>().loadCourses();
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
      appBar: AppBar(
        title: const Text('Courses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: Consumer<CourseProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingCourses && provider.courses.isEmpty) {
            return SkeletonList(
              itemCount: 5,
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
            );
          }

          if (provider.coursesError != null && provider.courses.isEmpty) {
            return ErrorDisplayWidget.fromMessage(
              message: provider.coursesError!,
              onRetry: () => provider.refreshCourses(),
            );
          }

          if (provider.courses.isEmpty) {
            return EmptyStateWidget.courses(
              onExplore: () => provider.refreshCourses(),
            );
          }

          // Group courses by category (level)
          final groupedCourses = provider.coursesByCategory;
          final categories = groupedCourses.keys.toList();

          return RefreshIndicator(
            onRefresh: () => provider.refreshCourses(),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: categories.length +
                  (provider.isLoadingCourses ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == categories.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final category = categories[index];
                final courses = groupedCourses[category]!;

                return _CategorySection(
                  title: category,
                  courses: courses,
                  onCourseTap: (courseId) =>
                      _navigateToCourseDetail(context, courseId),
                );
              },
            ),
          );
        },
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
  final String title;
  final List<CourseEntity> courses;
  final Function(String courseId) onCourseTap;

  const _CategorySection({
    Key? key,
    required this.title,
    required this.courses,
    required this.onCourseTap,
  }) : super(key: key);

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
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

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
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

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor(title);

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
                  color: categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getCategoryIcon(title),
                  color: categoryColor,
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
                      '${courses.length} ${courses.length == 1 ? 'course' : 'courses'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to full category view
                },
                child: const Text('See All'),
              ),
            ],
          ),
        ),

        // Horizontal Course List
        SizedBox(
          height: 280,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];
              return _HorizontalCourseCard(
                course: course,
                onTap: () => onCourseTap(course.id),
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
/// Compact card design for horizontal scrolling
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
    return Container(
      width: 200,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Card(
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
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 4),

                      // Language chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          course.language,
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Stats row
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.amber[700],
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${course.totalXp} XP',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.book_outlined,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${course.totalLessons}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),

                      // Progress or Enroll indicator
                      const SizedBox(height: 8),
                      if (course.isEnrolled == true) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (course.userProgress ?? 0) / 100,
                            backgroundColor: Colors.grey[300],
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${course.userProgress?.toStringAsFixed(0) ?? '0'}% Complete',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Start Learning',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
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

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.school,
          size: 40,
          color: Colors.grey[400],
        ),
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
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filters',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          // Language Filter
          const Text('Language', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('All'),
                selected: provider.selectedLanguage == null,
                onSelected: (_) {
                  provider.filterByLanguage(null);
                  Navigator.pop(context);
                },
              ),
              FilterChip(
                label: const Text('English'),
                selected: provider.selectedLanguage == 'English',
                onSelected: (_) {
                  provider.filterByLanguage('English');
                  Navigator.pop(context);
                },
              ),
              FilterChip(
                label: const Text('Spanish'),
                selected: provider.selectedLanguage == 'Spanish',
                onSelected: (_) {
                  provider.filterByLanguage('Spanish');
                  Navigator.pop(context);
                },
              ),
              FilterChip(
                label: const Text('Vietnamese'),
                selected: provider.selectedLanguage == 'Vietnamese',
                onSelected: (_) {
                  provider.filterByLanguage('Vietnamese');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Level Filter
          const Text('Level', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('All'),
                selected: provider.selectedLevel == null,
                onSelected: (_) {
                  provider.filterByLevel(null);
                  Navigator.pop(context);
                },
              ),
              FilterChip(
                label: const Text('Beginner'),
                selected: provider.selectedLevel == 'Beginner',
                onSelected: (_) {
                  provider.filterByLevel('Beginner');
                  Navigator.pop(context);
                },
              ),
              FilterChip(
                label: const Text('Intermediate'),
                selected: provider.selectedLevel == 'Intermediate',
                onSelected: (_) {
                  provider.filterByLevel('Intermediate');
                  Navigator.pop(context);
                },
              ),
              FilterChip(
                label: const Text('Advanced'),
                selected: provider.selectedLevel == 'Advanced',
                onSelected: (_) {
                  provider.filterByLevel('Advanced');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Clear Filters Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                provider.clearFilters();
                Navigator.pop(context);
              },
              child: const Text('Clear All Filters'),
            ),
          ),
        ],
      ),
    );
  }
}
