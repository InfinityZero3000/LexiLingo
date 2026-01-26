import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';

/// Course Detail Screen
/// Shows course roadmap with units and lessons
class CourseDetailScreen extends StatefulWidget {
  final String courseId;

  const CourseDetailScreen({
    Key? key,
    required this.courseId,
  }) : super(key: key);

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CourseProvider>().loadCourseDetail(widget.courseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<CourseProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingDetail) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.detailError != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    provider.detailError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.loadCourseDetail(widget.courseId),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final course = provider.courseDetail;
          if (course == null) {
            return const Center(child: Text('Course not found'));
          }

          return CustomScrollView(
            slivers: [
              // App Bar with Course Header
              SliverAppBar(
                expandedHeight: 250,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    course.title,
                    style: const TextStyle(
                      shadows: [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 3,
                          color: Colors.black45,
                        ),
                      ],
                    ),
                  ),
                  background: course.thumbnailUrl != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              course.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.school, size: 64),
                                );
                              },
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.7),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          color: Theme.of(context).primaryColor,
                          child: const Icon(Icons.school, size: 64, color: Colors.white),
                        ),
                ),
              ),

              // Course Info
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Description
                      if (course.description != null) ...[
                        Text(
                          course.description!,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Course Stats
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _StatChip(
                            icon: Icons.language,
                            label: course.language,
                          ),
                          _StatChip(
                            icon: Icons.bar_chart,
                            label: course.level,
                          ),
                          _StatChip(
                            icon: Icons.star,
                            label: '${course.totalXp} XP',
                          ),
                          _StatChip(
                            icon: Icons.access_time,
                            label: '${course.estimatedDuration} min',
                          ),
                          _StatChip(
                            icon: Icons.book,
                            label: '${course.totalLessons} lessons',
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Progress (if enrolled)
                      if (course.isEnrolled == true) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Your Progress',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: (course.userProgress ?? 0) / 100,
                                  minHeight: 8,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${course.userProgress?.toStringAsFixed(0) ?? '0'}% Complete',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Enroll Button (if not enrolled)
                      if (course.isEnrolled != true) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: provider.isEnrolling
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                              provider.isEnrolling ? 'Enrolling...' : 'Start Learning',
                            ),
                            onPressed: provider.isEnrolling
                                ? null
                                : () => _enrollInCourse(context, provider),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Roadmap Header
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Learning Roadmap',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // Units List
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final unit = course.units[index];
                    return _UnitCard(
                      unit: unit,
                      unitNumber: index + 1,
                    );
                  },
                  childCount: course.units.length,
                ),
              ),

              // Bottom Padding
              const SliverToBoxAdapter(
                child: SizedBox(height: 24),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _enrollInCourse(BuildContext context, CourseProvider provider) async {
    provider.clearEnrollmentMessages();
    
    final success = await provider.enrollInCourse(widget.courseId);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.enrollmentSuccess ?? 'Successfully enrolled!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.enrollmentError ?? 'Failed to enroll'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Stat Chip Widget
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({
    Key? key,
    required this.icon,
    required this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// Unit Card Widget
class _UnitCard extends StatelessWidget {
  final UnitWithLessonsEntity unit;
  final int unitNumber;

  const _UnitCard({
    Key? key,
    required this.unit,
    required this.unitNumber,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _parseColor(unit.backgroundColor),
          child: Text(
            '$unitNumber',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          unit.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: unit.description != null
            ? Text(
                unit.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        children: unit.lessons.map((lesson) {
          return _LessonTile(lesson: lesson);
        }).toList(),
      ),
    );
  }

  Color _parseColor(String? colorString) {
    if (colorString == null || colorString.isEmpty) {
      return Colors.blue;
    }
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.blue;
    }
  }
}

/// Lesson Tile Widget
class _LessonTile extends StatelessWidget {
  final LessonInRoadmapEntity lesson;

  const _LessonTile({
    Key? key,
    required this.lesson,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isLocked = lesson.isLocked ?? false;
    final isCompleted = lesson.isCompleted ?? false;

    return ListTile(
      leading: _getLessonIcon(lesson.lessonType, isLocked, isCompleted),
      title: Text(
        lesson.title,
        style: TextStyle(
          color: isLocked ? Colors.grey : null,
          decoration: isCompleted ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // XP Badge
          Chip(
            avatar: const Icon(Icons.star, size: 16),
            label: Text('${lesson.xpReward}'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          // Status Icon
          if (isCompleted)
            const Icon(Icons.check_circle, color: Colors.green)
          else if (isLocked)
            const Icon(Icons.lock, color: Colors.grey)
          else
            const Icon(Icons.play_circle_outline, color: Colors.blue),
        ],
      ),
      onTap: isLocked ? null : () {
        // TODO: Navigate to lesson
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opening lesson: ${lesson.title}'),
          ),
        );
      },
    );
  }

  Widget _getLessonIcon(String lessonType, bool isLocked, bool isCompleted) {
    IconData iconData;
    Color color;

    if (isLocked) {
      iconData = Icons.lock;
      color = Colors.grey;
    } else if (isCompleted) {
      iconData = Icons.check_circle;
      color = Colors.green;
    } else {
      switch (lessonType.toLowerCase()) {
        case 'vocabulary':
          iconData = Icons.school;
          color = Colors.blue;
          break;
        case 'grammar':
          iconData = Icons.menu_book;
          color = Colors.orange;
          break;
        case 'listening':
          iconData = Icons.headphones;
          color = Colors.purple;
          break;
        case 'speaking':
          iconData = Icons.mic;
          color = Colors.red;
          break;
        case 'reading':
          iconData = Icons.book;
          color = Colors.teal;
          break;
        case 'writing':
          iconData = Icons.edit;
          color = Colors.indigo;
          break;
        case 'quiz':
          iconData = Icons.quiz;
          color = Colors.amber;
          break;
        default:
          iconData = Icons.article;
          color = Colors.grey;
      }
    }

    return Icon(iconData, color: color);
  }
}
