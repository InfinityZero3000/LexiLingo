import '../../../../core/network/api_client.dart';
import '../../../../core/services/local_cache_service.dart';
import '../../domain/entities/proficiency_entity.dart';

List<Map<String, int>> buildPlacementAnswerPayload(Map<String, int> answers) {
  final payload = <Map<String, int>>[];

  for (final entry in answers.entries) {
    final questionId = int.tryParse(entry.key);
    if (questionId == null) continue;

    payload.add({'question_id': questionId, 'selected_option': entry.value});
  }

  payload.sort((a, b) => a['question_id']!.compareTo(b['question_id']!));
  return payload;
}

/// Data source for proficiency assessment API calls
class ProficiencyDataSource {
  final ApiClient _apiClient;
  final LocalCacheService _cache;
  static const String _profileCacheKey = 'proficiency:profile:v1';

  ProficiencyDataSource({required ApiClient apiClient})
    : _apiClient = apiClient,
      _cache = LocalCacheService.instance;

  /// Get user's proficiency profile
  Future<ProficiencyProfile> getProfile() async {
    final cached = await _cache.getOrFetch(
      key: _profileCacheKey,
      type: 'game',
      fetchFn: () => _apiClient.get('/proficiency/profile'),
    );
    final response = cached ?? await _apiClient.get('/proficiency/profile');
    return ProficiencyProfile.fromJson(response);
  }

  /// Record exercise results for proficiency tracking
  Future<ExerciseRecordResult> recordExercises(
    List<Map<String, dynamic>> results,
  ) async {
    final response = await _apiClient.post(
      '/proficiency/record-exercises',
      body: results,
    );
    await _cache.invalidate(_profileCacheKey);
    return ExerciseRecordResult.fromJson(response);
  }

  /// Check detailed requirements for next level
  Future<Map<String, dynamic>> checkLevelRequirements() async {
    return await _apiClient.get('/proficiency/level-check');
  }

  /// Get all level thresholds
  Future<Map<String, dynamic>> getLevelThresholds() async {
    final cached = await _cache.getOrFetch(
      key: 'proficiency:thresholds:v1',
      type: 'dictionary',
      fetchFn: () => _apiClient.get('/proficiency/level-thresholds'),
    );
    return cached ?? await _apiClient.get('/proficiency/level-thresholds');
  }

  /// Get level change history
  Future<Map<String, dynamic>> getLevelHistory({int limit = 10}) async {
    return await _apiClient.get('/proficiency/history?limit=$limit');
  }

  /// Get placement test questions
  Future<Map<String, dynamic>> getPlacementTest() async {
    return await _apiClient.get('/proficiency/placement-test');
  }

  /// Submit placement test answers
  Future<Map<String, dynamic>> submitPlacementTest({
    required Map<String, int> answers,
    required int timeTakenSeconds,
  }) async {
    return await _apiClient.post(
      '/proficiency/placement-test/submit',
      body: {'answers': buildPlacementAnswerPayload(answers)},
    );
  }
}
