import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';

/// Course Progress Card Widget
/// Displays progress for a single course
class CourseProgressCard extends StatelessWidget {
  final CourseProgressDetail courseProgress;
  final VoidCallback? onTap;

  const CourseProgressCard({
    super.key,
    required this.courseProgress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progressPercent = (courseProgress.progressPercentage / 100);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Course Title & XP
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      courseProgress.courseTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.star,
                        size: 16,
                        color: Colors.amber[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${courseProgress.totalXpEarned} XP',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber[700],
                            ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Progress Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${courseProgress.progressPercentage.toStringAsFixed(1)}% Complete',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${courseProgress.lessonsCompleted}/${courseProgress.totalLessons} lessons',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progressPercent,
                      minHeight: 8,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getProgressColor(courseProgress.progressPercentage),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Last Activity
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Last activity: ${_formatDate(courseProgress.lastActivityAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getProgressColor(double progress) {
    if (progress >= 80) {
      return Colors.green;
    } else if (progress >= 50) {
      return Colors.orange;
    } else {
      return Colors.blue;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat('MMM dd, yyyy').format(date);
    }
  }
}
