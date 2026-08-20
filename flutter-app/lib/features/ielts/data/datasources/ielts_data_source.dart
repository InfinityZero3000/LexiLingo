import '../../../../core/network/api_client.dart';
import '../../domain/entities/ielts_entities.dart';

/// IELTS mock-test API calls.
///
/// The list endpoints return an envelope whose `data` is a List, and ApiClient
/// only unwraps Map payloads — hence the `['data']` read here but not in the
/// single-object calls.
class IeltsDataSource {
  final ApiClient _apiClient;

  IeltsDataSource({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<IeltsTestSummary>> listTests({String? testType}) async {
    final query = testType != null ? '?test_type=$testType' : '';
    final response = await _apiClient.get('/ielts/tests$query');
    final data = response['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((t) => IeltsTestSummary.fromJson(Map<String, dynamic>.from(t)))
        .toList();
  }

  Future<IeltsAttemptState> startAttempt(
    String testId, {
    String skillScope = 'full',
  }) async {
    final response = await _apiClient.post(
      '/ielts/tests/$testId/start',
      body: {'skill_scope': skillScope},
    );
    return IeltsAttemptState.fromJson(response);
  }

  /// Merge answers server-side. Called while the learner works, so a failure
  /// here must not interrupt the sitting — the caller swallows it and the next
  /// autosave carries the same answers again.
  Future<void> saveAnswers(
    String attemptId,
    Map<String, dynamic> answers, {
    int timeSpentSeconds = 0,
  }) async {
    await _apiClient.patch(
      '/ielts/attempts/$attemptId/answers',
      body: {'answers': answers, 'time_spent_seconds': timeSpentSeconds},
    );
  }

  Future<Map<String, dynamic>> submit(
    String attemptId,
    Map<String, dynamic> answers, {
    int timeSpentSeconds = 0,
  }) async {
    return _apiClient.post(
      '/ielts/attempts/$attemptId/submit',
      body: {'answers': answers, 'time_spent_seconds': timeSpentSeconds},
    );
  }

  Future<IeltsResult> getResult(String attemptId) async {
    final response = await _apiClient.get('/ielts/attempts/$attemptId/result');
    return IeltsResult.fromJson(response);
  }

  Future<List<Map<String, dynamic>>> listAttempts({int limit = 20}) async {
    final response = await _apiClient.get('/ielts/attempts?limit=$limit');
    final data = response['data'];
    if (data is! List) return const [];
    return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
}
