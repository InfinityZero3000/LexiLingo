import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_attempt.dart';
import 'package:lexilingo_app/features/learning/domain/entities/answer_response.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_complete.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';

/// Learning Repository Interface
/// Defines the contract for learning operations
abstract class LearningRepository {
  Future<Either<Failure, LessonAttempt>> startLesson(String lessonId);

  Future<Either<Failure, AnswerResponse>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String questionType,
    required dynamic userAnswer,
    required int timeSpentMs,
    bool hintUsed,
    double? confidenceScore,
  });

  Future<Either<Failure, LessonComplete>> completeLesson(String attemptId);

  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(String courseId);

  Future<Either<Failure, LessonEntity>> getLessonContent(String lessonId);
}
