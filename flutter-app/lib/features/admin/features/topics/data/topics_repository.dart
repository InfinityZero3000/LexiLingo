import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_paged_list.dart';

const topicDifficulties = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

class TopicItem {
  const TopicItem({
    required this.storyId,
    required this.titleEn,
    required this.titleVi,
    required this.difficulty,
    required this.category,
    required this.minutes,
    this.iconKey,
    this.suggestedPrompts = const [],
    this.tags = const [],
  });

  final String storyId;
  final String titleEn;
  final String titleVi;
  final String difficulty;
  final String category;
  final int minutes;
  final String? iconKey;
  final List<String> suggestedPrompts;
  final List<String> tags;

  static List<String> _strings(Object? raw) => [
    for (final e in (raw as List? ?? const [])) e.toString(),
  ];

  factory TopicItem.fromJson(Map<String, dynamic> j) {
    final title = j['title'];
    final titles = title is Map ? title : const {};
    return TopicItem(
      storyId: j['story_id']?.toString() ?? '',
      titleEn: (titles['en'] ?? (title is String ? title : '')).toString(),
      titleVi: (titles['vi'] ?? titles['en'] ?? '').toString(),
      difficulty: j['difficulty_level']?.toString() ?? 'A2',
      category: j['category']?.toString() ?? '',
      minutes: (j['estimated_minutes'] as num?)?.toInt() ?? 15,
      iconKey: j['icon_key']?.toString(),
      suggestedPrompts: _strings(j['suggested_prompts']),
      tags: _strings(j['tags']),
    );
  }
}

/// Conversation topics live in ai-service; the backend proxies them, so the
/// app never needs the AI admin key.
class TopicsRepository {
  TopicsRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  static const path = '/admin/ai-proxy/topics';

  Future<PageResult<TopicItem>> list() async {
    final body = await _api.getData(path, params: {'limit': 200});
    final page = adminPage(body, TopicItem.fromJson, keys: const ['topics']);
    return PageResult(items: page.items, total: page.items.length);
  }

  Future<void> save({
    String? storyId,
    required String titleEn,
    required String titleVi,
    required String difficulty,
    required String category,
    required int minutes,
    required String iconKey,
    required List<String> suggestedPrompts,
    required List<String> tags,
    String? openingPrompt,
  }) async {
    await _api.post(
      path,
      data: {
        if (storyId != null && storyId.isNotEmpty) 'story_id': storyId,
        'title': {'en': titleEn, 'vi': titleVi.isEmpty ? titleEn : titleVi},
        'difficulty_level': difficulty,
        'category': category,
        'estimated_minutes': minutes,
        'icon_key': iconKey,
        if (openingPrompt != null && openingPrompt.isNotEmpty)
          'opening_prompt': openingPrompt,
        'suggested_prompts': suggestedPrompts,
        'tags': tags,
        'is_published': true,
      },
    );
  }
}
