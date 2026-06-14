import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import '../../data/models/story_model.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import '../utils/topic_icon_resolver.dart';

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
    final cefrColor = CefrBadge.colorForLevel(story.difficultyLevel.shortName);

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
                      color: cefrColor.withValues(alpha: 0.1),
                    ),
                    child: Center(
                      child: Icon(
                        TopicIconResolver.forStory(story),
                        size: 40,
                        color: cefrColor,
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
                            CefrBadge(
                              level: story.difficultyLevel.shortName,
                              size: CefrBadgeSize.small,
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
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(cefrColor),
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
                                  color: cefrColor.withValues(alpha: 0.7),
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
                          color: cefrColor,
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

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
