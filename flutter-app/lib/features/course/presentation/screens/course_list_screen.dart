import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';

/// Course List Screen
/// Displays all available courses with filters and pagination
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
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.coursesError != null && provider.courses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    provider.coursesError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.refreshCourses(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (provider.courses.isEmpty) {
            return const Center(
              child: Text('No courses available'),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.refreshCourses(),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: provider.courses.length + 
                         (provider.isLoadingCourses ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == provider.courses.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final course = provider.courses[index];
                return _CourseCard(
                  course: course,
                  onTap: () => _navigateToCourseDetail(context, course.id),
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

/// Course Card Widget
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
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            if (course.thumbnailUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    course.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.school, size: 64),
                      );
                    },
                  ),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    course.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Description
                  if (course.description != null)
                    Text(
                      course.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  
                  const SizedBox(height: 12),
                  
                  // Tags
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.language,
                        label: course.language,
                      ),
                      _InfoChip(
                        icon: Icons.bar_chart,
                        label: course.level,
                      ),
                      _InfoChip(
                        icon: Icons.star,
                        label: '${course.totalXp} XP',
                      ),
                      _InfoChip(
                        icon: Icons.access_time,
                        label: '${course.estimatedDuration} min',
                      ),
                      _InfoChip(
                        icon: Icons.book,
                        label: '${course.totalLessons} lessons',
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Enrollment status
                  if (course.isEnrolled == true) ...[
                    LinearProgressIndicator(
                      value: (course.userProgress ?? 0) / 100,
                      backgroundColor: Colors.grey[300],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${course.userProgress?.toStringAsFixed(0) ?? '0'}% Complete',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(
                      width: double.infinity,
                      child: Chip(
                        label: Text('Start Learning'),
                        avatar: Icon(Icons.play_arrow, size: 18),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Info Chip Widget
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    Key? key,
    required this.icon,
    required this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
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
