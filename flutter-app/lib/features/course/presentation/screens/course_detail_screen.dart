import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_roadmap_screen.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Course Detail Screen
/// Shows course roadmap with units and lessons
class CourseDetailScreen extends StatefulWidget {
  final String courseId;
  final String? heroTag;

  const CourseDetailScreen({super.key, required this.courseId, this.heroTag});

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
            return const Center(child: LottieLoadingWidget.medium());
          }

          if (provider.detailError != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.errorBright,
                  ),
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
              // Compact App Bar with smaller title
              SliverAppBar(
                pinned: true,
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                titleSpacing: 0,
                title: Text(
                  course.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.surface,
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
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
                      _buildCourseHeroCard(context, course),
                      const SizedBox(height: 16),

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
                          _StatChip(icon: Icons.bar_chart, label: course.level),
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
                        const SizedBox(height: 12),
                        // View Full Roadmap Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.account_tree_outlined),
                            label: const Text('View Full Roadmap'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LearningRoadmapScreen(
                                    courseId: course.id,
                                    courseTitle: course.title,
                                  ),
                                ),
                              );
                            },
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
                                    child: LottieLoadingWidget.tiny(),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                              provider.isEnrolling
                                  ? 'Enrolling...'
                                  : 'Start Learning',
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
                delegate: SliverChildBuilderDelegate((context, index) {
                  final unit = course.units[index];
                  return _UnitCard(
                    unit: unit,
                    unitNumber: index + 1,
                    courseId: course.id,
                  );
                }, childCount: course.units.length),
              ),

              // Bottom Padding
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _enrollInCourse(
    BuildContext context,
    CourseProvider provider,
  ) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    provider.clearEnrollmentMessages();

    final success = await provider.enrollInCourse(widget.courseId);

    if (!mounted) return;

    if (success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.enrollmentSuccess ?? 'Successfully enrolled!'),
          backgroundColor: AppColors.greenSuccessBright,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.enrollmentError ?? 'Failed to enroll'),
          backgroundColor: AppColors.errorBright,
        ),
      );
    }
  }

  Widget _buildCourseHeroCard(BuildContext context, CourseDetailEntity course) {
    final heroImage = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _buildCourseBackground(context, course),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: widget.heroTag != null
          ? Hero(tag: widget.heroTag!, child: heroImage)
          : heroImage,
    );
  }

  Widget _buildCourseBackground(
    BuildContext context,
    CourseDetailEntity course,
  ) {
    if (course.thumbnailUrl != null) {
      return Stack(
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
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      color: Theme.of(context).primaryColor,
      child: Icon(
        Icons.school,
        size: 64,
        color: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

/// Stat Chip Widget
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

/// Unit Card Widget
class _UnitCard extends StatelessWidget {
  final UnitWithLessonsEntity unit;
  final int unitNumber;
  final String courseId;

  const _UnitCard({
    required this.unit,
    required this.unitNumber,
    required this.courseId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _parseColor(unit.backgroundColor, isDark),
          child: Text(
            '$unitNumber',
            style: TextStyle(
              color: Theme.of(context).colorScheme.surface,
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
          return _LessonTile(lesson: lesson, courseId: courseId);
        }).toList(),
      ),
    );
  }

  Color _parseColor(String? colorString, bool isDark) {
    if (colorString == null || colorString.isEmpty) {
      return AppColorRoles.primary(isDark);
    }
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return AppColorRoles.primary(isDark);
    }
  }
}

/// Lesson Tile Widget
class _LessonTile extends StatelessWidget {
  final LessonInRoadmapEntity lesson;
  final String courseId;

  const _LessonTile({required this.lesson, required this.courseId});

  @override
  Widget build(BuildContext context) {
    final isLocked = lesson.isLocked ?? false;
    final isCompleted = lesson.isCompleted ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: _getLessonIcon(lesson.lessonType, isLocked, isCompleted, isDark),
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
            const Icon(Icons.check_circle, color: AppColors.greenSuccessBright)
          else if (isLocked)
            const Icon(Icons.lock, color: Colors.grey)
          else
            Icon(
              Icons.play_circle_outline,
              color: AppColorRoles.primary(isDark),
            ),
        ],
      ),
      onTap: isLocked
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LearningSessionScreen(
                    lessonId: lesson.id,
                    courseId: courseId,
                  ),
                ),
              );
            },
    );
  }

  Widget _getLessonIcon(
    String lessonType,
    bool isLocked,
    bool isCompleted,
    bool isDark,
  ) {
    IconData iconData;
    Color color;

    if (isLocked) {
      iconData = Icons.lock;
      color = Colors.grey;
    } else if (isCompleted) {
      iconData = Icons.check_circle;
      color = AppColors.greenSuccessBright;
    } else {
      switch (lessonType.toLowerCase()) {
        case 'vocabulary':
          iconData = Icons.school;
          color = AppColorRoles.primary(isDark);
          break;
        case 'grammar':
          iconData = Icons.menu_book;
          color = AppColors.orange;
          break;
        case 'listening':
          iconData = Icons.headphones;
          color = AppColors.purple;
          break;
        case 'speaking':
          iconData = Icons.mic;
          color = AppColors.errorBright;
          break;
        case 'reading':
          iconData = Icons.book;
          color = AppColors.teal;
          break;
        case 'writing':
          iconData = Icons.edit;
          color = Colors.indigo;
          break;
        case 'quiz':
          iconData = Icons.quiz;
          color = AppColors.warning;
          break;
        default:
          iconData = Icons.article;
          color = Colors.grey;
      }
    }

    return Icon(iconData, color: color);
  }
}
