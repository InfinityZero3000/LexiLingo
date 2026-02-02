import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_ui_components.dart';

/// Roadmap Node Widget
/// Displays a single lesson node in the roadmap with status indicators
class RoadmapNodeWidget extends StatelessWidget {
  final LessonProgressModel lesson;
  final bool isLastInUnit;
  final VoidCallback? onTap;

  const RoadmapNodeWidget({
    Key? key,
    required this.lesson,
    this.isLastInUnit = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Animated timeline indicator
          AnimatedTimelineNode(
            isLocked: lesson.isLocked,
            isCompleted: lesson.isCompleted,
            isCurrent: lesson.isCurrent,
            isLast: isLastInUnit,
            color: _getStatusColor(),
          ),
          const SizedBox(width: 16),
          // Glassmorphic lesson card
          Expanded(
            child: GlassmorphicLessonCard(
              title: lesson.title,
              description: lesson.description,
              isLocked: lesson.isLocked,
              isCompleted: lesson.isCompleted,
              isCurrent: lesson.isCurrent,
              starsEarned: lesson.starsEarned,
              bestScore: lesson.bestScore,
              attemptsCount: lesson.attemptsCount,
              statusColor: _getStatusColor(),
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (lesson.isLocked) {
      return Colors.grey;
    }
    if (lesson.isCompleted) {
      return Colors.green;
    }
    if (lesson.isCurrent) {
      return Colors.blue;
    }
    return Colors.grey[400]!;
  }
}
