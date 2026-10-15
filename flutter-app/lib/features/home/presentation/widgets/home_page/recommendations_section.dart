import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';

class RecommendationItem {
  const RecommendationItem({
    required this.itemId,
    required this.itemType,
    required this.title,
    required this.reason,
    this.topic,
    this.level,
    this.payload = const {},
  });

  final String itemId;
  final String itemType;
  final String title;
  final String reason;
  final String? topic;
  final String? level;
  final Map<String, dynamic> payload;

  factory RecommendationItem.fromJson(Map<String, dynamic> json) {
    return RecommendationItem(
      itemId: json['item_id'] as String? ?? '',
      itemType: json['item_type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      topic: json['topic'] as String?,
      level: json['level'] as String?,
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// "Gợi ý cho bạn" — top-K from RecGraph.
///
/// ponytail: fetches once in initState instead of joining HomeProvider. The
/// list is cached server-side per learner-state epoch, so a per-pull refresh
/// would mostly re-read the same cache entry. Move it into HomeProvider if
/// pull-to-refresh ever needs to reset it.
class RecommendationsSection extends StatefulWidget {
  const RecommendationsSection({super.key});

  @override
  State<RecommendationsSection> createState() => _RecommendationsSectionState();
}

class _RecommendationsSectionState extends State<RecommendationsSection> {
  late final Future<List<RecommendationItem>> _future = _load();

  Future<List<RecommendationItem>> _load() async {
    if (!sl.isRegistered<ApiClient>()) return const [];
    final response = await sl<ApiClient>().get(
      '/recommendations?surface=home&limit=8',
      timeout: const Duration(seconds: 8),
    );
    final items = (response['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((raw) => RecommendationItem.fromJson(raw.cast<String, dynamic>()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecommendationItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 132,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              itemBuilder: (context, _) => Container(
                width: 220,
                margin: const EdgeInsets.only(right: 12),
                child: const CardSkeleton(isHorizontal: false),
              ),
            ),
          );
        }

        final items = snapshot.data ?? const <RecommendationItem>[];
        // An empty or failed list renders nothing rather than an error card:
        // recommendations are an enhancement, never a blocker on Home.
        if (items.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 132,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _RecommendationCard(item: items[index]),
          ),
        );
      },
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.item});

  final RecommendationItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tactile =
        theme.extension<AppTactileTheme>() ?? AppTactileTheme.from(theme);

    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: tactile.decoration(
          variant: TactileSurfaceVariant.interactive,
          fill: theme.colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _iconFor(item.itemType),
                  size: 16,
                  color: AppColorRoles.primary(isDark),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _labelFor(item.itemType),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColorRoles.textSecondary(isDark),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.level != null)
                  Text(
                    item.level!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColorRoles.primary(isDark),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColorRoles.textPrimary(isDark),
              ),
            ),
            const Spacer(),
            Text(
              item.reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColorRoles.textSecondary(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    trackContentInteraction(
      itemType: item.itemType,
      itemId: item.itemId,
      action: 'open',
      topic: item.topic,
      source: 'home_recommendations',
    );

    switch (item.itemType) {
      case 'course':
        LearnerRoute.push(
          context,
          (_) => CourseDetailScreen(courseId: item.itemId),
        );
      case 'lesson':
        final courseId = item.payload['course_id'] as String?;
        if (courseId == null) return;
        LearnerRoute.push(
          context,
          (_) =>
              LearningSessionScreen(lessonId: item.itemId, courseId: courseId),
        );
      case 'vocab':
        Navigator.pushNamed(context, '/vocabulary/review');
      case 'video':
        Navigator.pushNamed(context, '/youtube');
      case 'news':
        Navigator.pushNamed(context, '/news');
    }
  }

  IconData _iconFor(String type) => switch (type) {
    'course' => Icons.school_outlined,
    'lesson' => Icons.play_lesson_outlined,
    'vocab' => Icons.style_outlined,
    'video' => Icons.play_circle_outline,
    'news' => Icons.article_outlined,
    _ => Icons.lightbulb_outline,
  };

  String _labelFor(String type) => switch (type) {
    'course' => 'home.recTypeCourse'.tr(),
    'lesson' => 'home.recTypeLesson'.tr(),
    'vocab' => 'home.recTypeVocab'.tr(),
    'video' => 'home.recTypeVideo'.tr(),
    'news' => 'home.recTypeNews'.tr(),
    _ => 'home.recTypeOther'.tr(),
  };
}
