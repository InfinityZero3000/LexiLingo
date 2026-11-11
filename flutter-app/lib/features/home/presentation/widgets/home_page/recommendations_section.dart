import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/card_art_painter.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/section_title.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';

class RecommendationItem {
  const RecommendationItem({
    required this.itemId,
    required this.itemType,
    required this.title,
    required this.reason,
    this.reasonCode,
    this.reasonArgs = const {},
    this.topic,
    this.level,
    this.payload = const {},
  });

  final String itemId;
  final String itemType;
  final String title;
  final String reason;
  final String? reasonCode;
  final Map<String, String> reasonArgs;
  final String? topic;
  final String? level;
  final Map<String, dynamic> payload;

  /// Localized on the client; `reason` (server text) only covers older cached
  /// items and codes this build does not know.
  String get localizedReason {
    final key = switch (reasonCode) {
      'due' => 'home.recReasonDue',
      'topic' => 'home.recReasonTopic',
      'gap' => 'home.recReasonGap',
      'level' => 'home.recReasonLevel',
      'similar' => 'home.recReasonSimilar',
      'default' => 'home.recReasonDefault',
      _ => null,
    };
    return key == null ? reason : key.tr(namedArgs: reasonArgs);
  }

  factory RecommendationItem.fromJson(Map<String, dynamic> json) {
    return RecommendationItem(
      itemId: json['item_id'] as String? ?? '',
      itemType: json['item_type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      reasonCode: json['reason_code'] as String?,
      reasonArgs:
          (json['reason_args'] as Map?)?.map(
            (key, value) => MapEntry('$key', '$value'),
          ) ??
          const {},
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

  // Random start, then cycle: every visit looks different but neighbours never
  // share a colour.
  static const _palette = [
    AppColors.primary,
    AppColors.greenSuccess,
    AppColors.purple,
    AppColors.deepOrange,
    AppColors.teal,
  ];
  final int _paletteOffset = Random().nextInt(_palette.length);

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
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final items = snapshot.data ?? const <RecommendationItem>[];
        // An empty or failed list renders nothing — heading included — rather
        // than an error card or an orphan title: recommendations are an
        // enhancement, never a blocker on Home.
        if (!loading && items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(title: 'home.recommendedForYou'.tr()),
              const SizedBox(height: 8),
              SizedBox(
                height: 132,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: loading ? 3 : items.length,
                  itemBuilder: (context, index) => loading
                      ? Container(
                          width: 220,
                          margin: const EdgeInsets.only(right: 12),
                          child: const CardSkeleton(isHorizontal: false),
                        )
                      : _RecommendationCard(
                          item: items[index],
                          slot: (index + _paletteOffset) % _palette.length,
                          accent:
                              _palette[(index + _paletteOffset) %
                                  _palette.length],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.item,
    required this.accent,
    required this.slot,
  });

  final RecommendationItem item;
  final Color accent;
  final int slot;

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
        decoration: tactile.decoration(
          variant: TactileSurfaceVariant.interactive,
          accent: accent,
          fill: Color.alphaBlend(
            accent.withValues(alpha: isDark ? 0.16 : 0.10),
            theme.colorScheme.surface,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CustomPaint(
                  painter: CardArtPainter(
                    accent: accent,
                    base: theme.colorScheme.surface,
                    motif: slot,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _iconFor(item.itemType),
                            size: 16,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _labelFor(item.itemType),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColorRoles.textPrimary(isDark),
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.level != null)
                          Text(
                            item.level!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
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
                      item.localizedReason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColorRoles.textSecondary(isDark),
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
