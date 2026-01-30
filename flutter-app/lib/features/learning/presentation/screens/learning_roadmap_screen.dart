import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/roadmap_node_widget.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/roadmap_header_widget.dart';

/// Learning Roadmap Screen
/// Displays the course progress as a visual roadmap/tree structure
class LearningRoadmapScreen extends StatefulWidget {
  final String courseId;
  final String courseTitle;

  const LearningRoadmapScreen({
    Key? key,
    required this.courseId,
    required this.courseTitle,
  }) : super(key: key);

  @override
  State<LearningRoadmapScreen> createState() => _LearningRoadmapScreenState();
}

class _LearningRoadmapScreenState extends State<LearningRoadmapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LearningProvider>().loadRoadmap(widget.courseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<LearningProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingRoadmap) {
            return _buildLoadingState();
          }

          if (provider.roadmapError != null) {
            return _buildErrorState(provider.roadmapError!, provider);
          }

          final roadmap = provider.courseRoadmap;
          if (roadmap == null) {
            return _buildEmptyState();
          }

          return _buildRoadmapContent(context, roadmap);
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading roadmap...'),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error, LearningProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load roadmap',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => provider.loadRoadmap(widget.courseId),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.school_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No lessons available',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for new content',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadmapContent(BuildContext context, CourseRoadmapModel roadmap) {
    return CustomScrollView(
      slivers: [
        // Header with course info and progress
        SliverToBoxAdapter(
          child: RoadmapHeaderWidget(
            roadmap: roadmap,
            onBack: () => Navigator.pop(context),
          ),
        ),

        // Units and Lessons
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final unit = roadmap.units[index];
                return _buildUnitSection(context, unit, index, roadmap.units.length);
              },
              childCount: roadmap.units.length,
            ),
          ),
        ),

        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }

  Widget _buildUnitSection(
    BuildContext context,
    UnitRoadmapModel unit,
    int unitIndex,
    int totalUnits,
  ) {
    final isLastUnit = unitIndex == totalUnits - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Unit Header
        Container(
          margin: const EdgeInsets.only(top: 24, bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _parseColor(unit.backgroundColor),
                _parseColor(unit.backgroundColor).withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _parseColor(unit.backgroundColor).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${unit.unitNumber}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (unit.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        unit.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildUnitProgress(unit),
            ],
          ),
        ),

        // Lessons in this unit
        ...unit.lessons.asMap().entries.map((entry) {
          final lessonIndex = entry.key;
          final lesson = entry.value;
          final isLastLesson = lessonIndex == unit.lessons.length - 1;

          return RoadmapNodeWidget(
            lesson: lesson,
            isLastInUnit: isLastLesson && isLastUnit,
            onTap: lesson.isLocked
                ? null
                : () => _navigateToLesson(context, lesson),
          );
        }),
      ],
    );
  }

  Widget _buildUnitProgress(UnitRoadmapModel unit) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: unit.completionPercentage / 100,
            strokeWidth: 4,
            backgroundColor: Colors.white.withOpacity(0.3),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          Text(
            '${unit.completedLessons}/${unit.totalLessons}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToLesson(BuildContext context, LessonProgressModel lesson) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LearningSessionScreen(
          lessonId: lesson.lessonId,
          courseId: widget.courseId,
        ),
      ),
    );
  }

  Color _parseColor(String hexColor) {
    try {
      final hex = hexColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }
}
