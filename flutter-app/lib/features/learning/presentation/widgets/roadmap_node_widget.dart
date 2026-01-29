import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';

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
          // Timeline indicator
          _buildTimelineIndicator(context),
          const SizedBox(width: 16),
          // Lesson card
          Expanded(
            child: _buildLessonCard(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineIndicator(BuildContext context) {
    final color = _getStatusColor();
    
    return SizedBox(
      width: 48,
      child: Column(
        children: [
          // Top line
          Container(
            width: 3,
            height: 12,
            color: color.withOpacity(0.3),
          ),
          // Circle node
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: lesson.isLocked ? Colors.grey[300] : color,
              shape: BoxShape.circle,
              border: Border.all(
                color: color,
                width: 3,
              ),
              boxShadow: lesson.isCurrent
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: _buildNodeIcon(),
            ),
          ),
          // Bottom line
          if (!isLastInUnit)
            Expanded(
              child: Container(
                width: 3,
                color: color.withOpacity(0.3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeIcon() {
    if (lesson.isLocked) {
      return const Icon(
        Icons.lock,
        size: 16,
        color: Colors.grey,
      );
    }
    if (lesson.isCompleted) {
      return const Icon(
        Icons.check,
        size: 18,
        color: Colors.white,
      );
    }
    if (lesson.isCurrent) {
      return Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildLessonCard(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getStatusColor();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: lesson.isLocked
              ? Colors.grey[100]
              : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: lesson.isCurrent
                ? color
                : lesson.isLocked
                    ? Colors.grey[300]!
                    : Colors.grey[200]!,
            width: lesson.isCurrent ? 2 : 1,
          ),
          boxShadow: lesson.isLocked
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Opacity(
          opacity: lesson.isLocked ? 0.6 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lesson.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: lesson.isLocked ? Colors.grey : null,
                      ),
                    ),
                  ),
                  if (lesson.isCompleted) _buildStars(),
                ],
              ),

              if (lesson.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  lesson.description!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Progress row
              Row(
                children: [
                  // Status badge
                  _buildStatusBadge(color),
                  const Spacer(),
                  // Score & Attempts
                  if (lesson.bestScore != null) ...[
                    Icon(
                      Icons.emoji_events,
                      size: 16,
                      color: Colors.amber[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${lesson.bestScore!.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.amber[700],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (lesson.attemptsCount > 0) ...[
                    Icon(
                      Icons.replay,
                      size: 16,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${lesson.attemptsCount}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ],
              ),

              // Current lesson indicator
              if (lesson.isCurrent) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final isFilled = index < lesson.starsEarned;
        return Icon(
          isFilled ? Icons.star : Icons.star_border,
          size: 20,
          color: isFilled ? Colors.amber : Colors.grey[300],
        );
      }),
    );
  }

  Widget _buildStatusBadge(Color color) {
    String text;
    IconData icon;

    if (lesson.isLocked) {
      text = 'Locked';
      icon = Icons.lock_outline;
    } else if (lesson.isCompleted) {
      text = 'Completed';
      icon = Icons.check_circle_outline;
    } else if (lesson.isCurrent) {
      text = 'In Progress';
      icon = Icons.play_circle_outline;
    } else {
      text = 'Available';
      icon = Icons.circle_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
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
