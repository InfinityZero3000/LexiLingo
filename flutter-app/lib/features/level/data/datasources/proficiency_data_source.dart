import '../../../../core/network/api_client.dart';
import '../../domain/entities/proficiency_entity.dart';

/// Data source for proficiency assessment API calls
class ProficiencyDataSource {
  final ApiClient _apiClient;

  ProficiencyDataSource({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Get user's proficiency profile
  Future<ProficiencyProfile> getProfile() async {
    final response = await _apiClient.get('/proficiency/profile');
    return ProficiencyProfile.fromJson(response);
  }

  /// Record exercise results for proficiency tracking
  Future<ExerciseRecordResult> recordExercises(List<Map<String, dynamic>> results) async {
    final response = await _apiClient.post(
      '/proficiency/record-exercises',
      body: results,
    );
    return ExerciseRecordResult.fromJson(response);
  }

  /// Check detailed requirements for next level
  Future<Map<String, dynamic>> checkLevelRequirements() async {
    return await _apiClient.get('/proficiency/level-check');
  }

  /// Get all level thresholds
  Future<Map<String, dynamic>> getLevelThresholds() async {
    return await _apiClient.get('/proficiency/level-thresholds');
  }

  /// Get level change history
  Future<Map<String, dynamic>> getLevelHistory({int limit = 10}) async {
    return await _apiClient.get('/proficiency/history?limit=$limit');
  }
}
