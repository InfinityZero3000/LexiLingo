import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_attempt_model.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/data/models/answer_response_model.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_complete_model.dart';

/// Learning Remote Data Source
/// Handles API communication for learning session endpoints
abstract class LearningRemoteDataSource {
  /// POST /learning/lessons/{lesson_id}/start - Start or resume a lesson
  Future<ApiResponseEnvelope<LessonAttemptModel>> startLesson(String lessonId);

  /// POST /learning/attempts/{attempt_id}/answer - Submit an answer
  Future<ApiResponseEnvelope<AnswerResponseModel>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String questionType,
    required dynamic userAnswer,
    required int timeSpentMs,
    bool hintUsed = false,
    double? confidenceScore,
  });

  /// POST /learning/attempts/{attempt_id}/complete - Complete a lesson
  Future<ApiResponseEnvelope<LessonCompleteModel>> completeLesson(String attemptId);

  /// GET /learning/courses/{course_id}/roadmap - Get course roadmap
  Future<ApiResponseEnvelope<CourseRoadmapModel>> getCourseRoadmap(String courseId);
}

/// Implementation of LearningRemoteDataSource
class LearningRemoteDataSourceImpl implements LearningRemoteDataSource {
  final ApiClient _apiClient;

  LearningRemoteDataSourceImpl({required ApiClient apiClient}) : _apiClient = apiClient;

  @override
  Future<ApiResponseEnvelope<LessonAttemptModel>> startLesson(String lessonId) async {
    final response = await _apiClient.post('/learning/lessons/$lessonId/start');

    return ApiResponseEnvelope<LessonAttemptModel>.fromJson(
      response,
      (data) => LessonAttemptModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<ApiResponseEnvelope<AnswerResponseModel>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String questionType,
    required dynamic userAnswer,
    required int timeSpentMs,
    bool hintUsed = false,
    double? confidenceScore,
  }) async {
    final body = {
      'question_id': questionId,
      'question_type': questionType,
      'user_answer': userAnswer,
      'time_spent_ms': timeSpentMs,
      'hint_used': hintUsed,
      if (confidenceScore != null) 'confidence_score': confidenceScore,
    };

    final response = await _apiClient.post(
      '/learning/attempts/$attemptId/answer',
      body: body,
    );

    return ApiResponseEnvelope<AnswerResponseModel>.fromJson(
      response,
      (data) => AnswerResponseModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<ApiResponseEnvelope<LessonCompleteModel>> completeLesson(String attemptId) async {
    final response = await _apiClient.post('/learning/attempts/$attemptId/complete');

    return ApiResponseEnvelope<LessonCompleteModel>.fromJson(
      response,
      (data) => LessonCompleteModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<ApiResponseEnvelope<CourseRoadmapModel>> getCourseRoadmap(String courseId) async {
    final response = await _apiClient.get('/learning/courses/$courseId/roadmap');

    return ApiResponseEnvelope<CourseRoadmapModel>.fromJson(
      response,
      (data) => CourseRoadmapModel.fromJson(data as Map<String, dynamic>),
    );
  }
}
