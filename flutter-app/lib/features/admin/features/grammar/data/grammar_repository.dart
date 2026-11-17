import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_paged_list.dart';

class GrammarRule {
  const GrammarRule({
    required this.id,
    required this.title,
    required this.level,
    this.topic,
    this.summary,
    this.content = '',
    this.tags = const [],
    this.isActive = true,
  });

  final String id;
  final String title;
  final String level;
  final String? topic;
  final String? summary;
  final String content;
  final List<String> tags;
  final bool isActive;

  factory GrammarRule.fromJson(Map<String, dynamic> j) => GrammarRule(
    id: j['id']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    level: (j['level'] ?? j['cefr_level'] ?? 'A1').toString().toUpperCase(),
    topic: j['topic']?.toString(),
    summary: j['summary']?.toString(),
    content: j['content']?.toString() ?? '',
    tags: [for (final t in (j['tags'] as List? ?? const [])) t.toString()],
    isActive: j['is_active'] != false,
  );
}

class GrammarRepository {
  GrammarRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<PageResult<GrammarRule>> list(PageRequest request) async {
    final body = await _api.getData(
      ApiEndpoints.adminGrammar,
      params: PaginationStyle.limitOffset.query(request),
    );
    return adminPage(body, GrammarRule.fromJson);
  }

  Future<void> save({String? id, required Map<String, dynamic> data}) async {
    if (id == null) {
      await _api.post(ApiEndpoints.adminGrammar, data: data);
    } else {
      await _api.put('${ApiEndpoints.adminGrammar}/$id', data: data);
    }
  }
}
