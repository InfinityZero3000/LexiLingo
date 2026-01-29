import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_attempt_model.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/data/models/answer_response_model.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_complete_model.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';

/// Learning Repository Interface
/// Defines the contract for learning operations
abstract class LearningRepository {
  /// Start or resume a lesson
  Future<Either<Failure, LessonAttemptModel>> startLesson(String lessonId);

  /// Submit an answer for a question
  Future<Either<Failure, AnswerResponseModel>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String questionType,
    required dynamic userAnswer,
    required int timeSpentMs,
    bool hintUsed,
    double? confidenceScore,
  });

  /// Complete a lesson
  Future<Either<Failure, LessonCompleteModel>> completeLesson(String attemptId);

  /// Get course roadmap for progress visualization
  Future<Either<Failure, CourseRoadmapModel>> getCourseRoadmap(String courseId);

  /// Get lesson content with exercises (for offline use)
  Future<Either<Failure, LessonEntity>> getLessonContent(String lessonId);
}
