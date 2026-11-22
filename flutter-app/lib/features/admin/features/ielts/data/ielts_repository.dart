import 'package:lexilingo_app/core/network/envelope.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_paged_list.dart';

class IeltsTest {
  const IeltsTest({
    required this.id,
    required this.title,
    required this.testType,
    required this.skillScope,
    this.description,
    this.targetBand,
    this.isPublished = false,
    this.questionCount = 0,
    this.attemptCount = 0,
  });

  final String id;
  final String title;
  final String testType;
  final String skillScope;
  final String? description;
  final String? targetBand;
  final bool isPublished;
  final int questionCount;
  final int attemptCount;

  factory IeltsTest.fromJson(Map<String, dynamic> j) => IeltsTest(
    id: j['id']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    testType: j['test_type']?.toString() ?? '',
    skillScope: j['skill_scope']?.toString() ?? '',
    description: j['description']?.toString(),
    targetBand: j['target_band']?.toString(),
    isPublished: j['is_published'] == true,
    questionCount: (j['question_count'] as num?)?.toInt() ?? 0,
    attemptCount: (j['attempt_count'] as num?)?.toInt() ?? 0,
  );
}

class IeltsAttempt {
  const IeltsAttempt({
    required this.id,
    required this.userId,
    required this.testId,
    required this.status,
    this.overallBand,
    this.startedAt,
    this.submittedAt,
  });

  final String id;
  final String userId;
  final String testId;
  final String status;
  final double? overallBand;
  final DateTime? startedAt;
  final DateTime? submittedAt;

  factory IeltsAttempt.fromJson(Map<String, dynamic> j) => IeltsAttempt(
    id: j['attempt_id']?.toString() ?? '',
    userId: j['user_id']?.toString() ?? '',
    testId: j['test_id']?.toString() ?? '',
    status: j['status']?.toString() ?? '',
    overallBand: (j['overall_band'] as num?)?.toDouble(),
    startedAt: DateTime.tryParse(j['started_at']?.toString() ?? ''),
    submittedAt: DateTime.tryParse(j['submitted_at']?.toString() ?? ''),
  );
}

/// What validating a paper found: [problems] block publishing.
class IeltsValidation {
  const IeltsValidation({
    required this.publishable,
    required this.problems,
    required this.counts,
  });

  final bool publishable;
  final List<String> problems;
  final Map<String, int> counts;

  factory IeltsValidation.fromJson(Map<String, dynamic> j) => IeltsValidation(
    publishable: j['publishable'] == true,
    problems: [for (final p in (j['problems'] as List? ?? const [])) '$p'],
    counts: {
      for (final e in ((j['counts'] as Map?) ?? const {}).entries)
        e.key.toString(): (e.value as num?)?.toInt() ?? 0,
    },
  );
}

class IeltsRepository {
  IeltsRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  static const path = '/admin/ielts';

  Future<PageResult<IeltsTest>> listTests(PageRequest request) async =>
      adminPage(
        await _api.getData(
          '$path/tests',
          params: PaginationStyle.limitOffset.query(request),
        ),
        IeltsTest.fromJson,
      );

  /// The attempts route takes only `limit` (and an optional test).
  Future<PageResult<IeltsAttempt>> listAttempts({String? testId}) async {
    final page = adminPage(
      await _api.getData(
        '$path/attempts',
        params: {'limit': 100, if (testId != null) 'test_id': testId},
      ),
      IeltsAttempt.fromJson,
    );
    return PageResult(items: page.items, total: page.items.length);
  }

  Future<IeltsValidation> validate(String testId) async {
    final response = await _api.post('$path/tests/$testId/validate');
    final body = unwrapEnvelope(response);
    return IeltsValidation.fromJson(Map<String, dynamic>.from(body as Map));
  }
}
