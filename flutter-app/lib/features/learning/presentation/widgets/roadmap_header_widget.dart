import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Roadmap Header Widget
/// Displays course info, progress stats, and streak at the top of roadmap
class RoadmapHeaderWidget extends StatelessWidget {
  final CourseRoadmapModel roadmap;
  final VoidCallback onBack;

  const RoadmapHeaderWidget({
    super.key,
    required this.roadmap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Text(
                      roadmap.courseTitle,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.surface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildLevelBadge(roadmap.level),
                ],
              ),
            ),

            // Progress stats
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem(
                    icon: Icons.local_fire_department,
                    value: '${roadmap.currentStreak}',
                    label: 'Streak',
                    iconColor: AppColors.orange,
                  ),
                  _buildStatItem(
                    icon: Icons.star,
                    value: '${roadmap.totalXpEarned}',
                    label: 'XP',
                    iconColor: AppColors.warning,
                  ),
                  _buildStatItem(
                    icon: Icons.check_circle,
                    value:
                        '${roadmap.completedLessons}/${roadmap.totalLessons}',
                    label: 'Lessons',
                    iconColor: AppColors.greenSuccessBright,
                  ),
                  _buildStatItem(
                    icon: Icons.pie_chart,
                    value:
                        '${roadmap.completionPercentage.toStringAsFixed(0)}%',
                    label: 'Progress',
                    iconColor: Colors.blue,
                  ),
                ],
              ),
            ),

            // Overall progress bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Course Progress',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        '${roadmap.completionPercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: AppColors.surfaceLight,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: roadmap.completionPercentage / 100,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Curved bottom
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelBadge(String level) {
    Color badgeColor;
    switch (level.toLowerCase()) {
      case 'beginner':
        badgeColor = AppColors.greenSuccessBright;
        break;
      case 'intermediate':
        badgeColor = AppColors.orange;
        break;
      case 'advanced':
        badgeColor = AppColors.errorBright;
        break;
      default:
        badgeColor = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor, width: 1),
      ),
      child: Text(
        level.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: badgeColor,
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
  }) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.surfaceLight,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.surfaceLight),
        ),
      ],
    );
  }
}
