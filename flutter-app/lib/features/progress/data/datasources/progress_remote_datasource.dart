import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/progress/data/models/progress_model.dart';
import 'package:lexilingo_app/features/progress/data/models/streak_model.dart';

/// Progress Remote Data Source Interface
abstract class ProgressRemoteDataSource {
  Future<ProgressStatsModel> getMyProgress();
  Future<CourseProgressWithUnitsModel> getCourseProgress(String courseId);
  Future<LessonCompletionResultModel> completeLesson({
    required String lessonId,
    required double score,
  });
  Future<int> getTotalXp();
  
  // Streak methods
  Future<StreakModel> getMyStreak();
  Future<StreakUpdateResultModel> updateStreak();
  Future<Map<String, dynamic>> useStreakFreeze();
}

/// Progress Remote Data Source Implementation
class ProgressRemoteDataSourceImpl implements ProgressRemoteDataSource {
  final ApiClient apiClient;

  ProgressRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<ProgressStatsModel> getMyProgress() async {
    try {
      final response = await apiClient.get('/progress/me');
      return ProgressStatsModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<CourseProgressWithUnitsModel> getCourseProgress(String courseId) async {
    try {
      final response = await apiClient.get('/progress/courses/$courseId');
      return CourseProgressWithUnitsModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<LessonCompletionResultModel> completeLesson({
    required String lessonId,
    required double score,
  }) async {
    try {
      final response = await apiClient.post(
        '/progress/lessons/$lessonId/complete',
        body: {
          'lesson_id': lessonId,
          'score': score,
        },
      );
      return LessonCompletionResultModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<int> getTotalXp() async {
    try {
      final response = await apiClient.get('/progress/xp');
      return response['total_xp'] ?? 0;
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================================
  // Streak Methods
  // ============================================================================

  @override
  Future<StreakModel> getMyStreak() async {
    try {
      final response = await apiClient.get('/progress/streak');
      return StreakModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<StreakUpdateResultModel> updateStreak() async {
    try {
      final response = await apiClient.post('/progress/streak/update', body: {});
      return StreakUpdateResultModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> useStreakFreeze() async {
    try {
      final response = await apiClient.post('/progress/streak/freeze', body: {});
      return response;
    } catch (e) {
      rethrow;
    }
  }
}
