import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_ui_components.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Roadmap Node Widget
/// Displays a single lesson node in the roadmap with status indicators
class RoadmapNodeWidget extends StatelessWidget {
  final LessonProgressModel lesson;
  final bool isLastInUnit;
  final VoidCallback? onTap;

  const RoadmapNodeWidget({
    super.key,
    required this.lesson,
    this.isLastInUnit = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(context);
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
            color: statusColor,
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
              statusColor: statusColor,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (lesson.isLocked) {
      return Colors.grey;
    }
    if (lesson.isCompleted) {
      return AppColors.greenSuccessBright;
    }
    if (lesson.isCurrent) {
      return AppColorRoles.primary(isDark);
    }
    return Colors.grey[400]!;
  }
}
