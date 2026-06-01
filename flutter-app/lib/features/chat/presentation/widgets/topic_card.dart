import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import '../../data/models/story_model.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Enhanced Topic Card for Selection Screen
class TopicCard extends StatelessWidget {
  final StoryListItem story;
  final double? progress;
  final bool isWarming;
  final VoidCallback onTap;

  const TopicCard({
    super.key,
    required this.story,
    this.progress,
    this.isWarming = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getDifficultyColor(story.difficultyLevel);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: isWarming ? null : onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Image/Icon Section
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                    ),
                    child: Center(
                      child: Icon(
                        _getCategoryIcon(story.category),
                        size: 40,
                        color: color,
                      ),
                    ),
                  ),
                ),

                // Info Section
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Difficulty & Category Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                story.difficultyLevel.shortName,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              _capitalize(story.category),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Title
                        Text(
                          story.title.en,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),

                        // Progress Bar (if available)
                        if (progress != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],

                        // Footer: Time & Tags
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${story.estimatedMinutes}m',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                            const Spacer(),
                            if (story.tags.isNotEmpty)
                              Text(
                                '#${story.tags.first}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: color.withValues(alpha: 0.7),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Warming Overlay
            if (isWarming)
              Container(
                color: AppColors.surfaceLight,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: LottieLoadingWidget.tiny(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'chat.preparing'.tr(),
                        style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getDifficultyColor(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.A1:
        return AppColors.greenSuccessBright;
      case DifficultyLevel.A2:
        return Colors.blue;
      case DifficultyLevel.B1:
        return AppColors.orange;
      case DifficultyLevel.B2:
        return AppColors.deepOrange;
      case DifficultyLevel.C1:
        return AppColors.errorBright;
      case DifficultyLevel.C2:
        return AppColors.purple;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'travel':
        return Icons.flight;
      case 'business':
      case 'work':
        return Icons.business_center;
      case 'daily_life':
      case 'housing':
        return Icons.home;
      case 'food':
      case 'cafe':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_bag;
      case 'finance':
        return Icons.account_balance_wallet;
      case 'health':
        return Icons.local_hospital;
      case 'education':
        return Icons.school;
      case 'technology':
        return Icons.devices;
      case 'services':
        return Icons.support_agent;
      case 'culture':
        return Icons.museum;
      case 'leisure':
        return Icons.sports_soccer;
      case 'social':
        return Icons.groups;
      case 'emergency':
        return Icons.emergency;
      case 'environment':
        return Icons.eco;
      case 'media':
        return Icons.mic;
      default:
        return Icons.chat_bubble;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
