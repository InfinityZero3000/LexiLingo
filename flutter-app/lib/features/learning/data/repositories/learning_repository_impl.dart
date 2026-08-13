import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failure_mapper.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/learning/data/datasources/learning_remote_datasource.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_attempt.dart';
import 'package:lexilingo_app/features/learning/domain/entities/answer_response.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_complete.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

/// Implementation of LearningRepository
class LearningRepositoryImpl implements LearningRepository {
  final LearningRemoteDataSource _remoteDataSource;

  LearningRepositoryImpl({required LearningRemoteDataSource remoteDataSource})
    : _remoteDataSource = remoteDataSource;

  @override
  Future<Either<Failure, LessonAttempt>> startLesson(
    String lessonId,
  ) async {
    try {
      final response = await _remoteDataSource.startLesson(lessonId);
      return Right(response.data);
    } catch (e) {
      return Left(mapFailure(e));
    }
  }

  @override
  Future<Either<Failure, AnswerResponse>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String questionType,
    required dynamic userAnswer,
    required int timeSpentMs,
    bool hintUsed = false,
    double? confidenceScore,
  }) async {
    try {
      final response = await _remoteDataSource.submitAnswer(
        attemptId: attemptId,
        questionId: questionId,
        questionType: questionType,
        userAnswer: userAnswer,
        timeSpentMs: timeSpentMs,
        hintUsed: hintUsed,
        confidenceScore: confidenceScore,
      );
      return Right(response.data);
    } catch (e) {
      return Left(mapFailure(e));
    }
  }

  @override
  Future<Either<Failure, LessonComplete>> completeLesson(
    String attemptId,
  ) async {
    try {
      final response = await _remoteDataSource.completeLesson(attemptId);
      return Right(response.data);
    } catch (e) {
      return Left(mapFailure(e));
    }
  }

  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(
    String courseId,
  ) async {
    try {
      final response = await _remoteDataSource.getCourseRoadmap(courseId);
      return Right(response.data);
    } catch (e) {
      return Left(mapFailure(e));
    }
  }

  @override
  Future<Either<Failure, LessonEntity>> getLessonContent(
    String lessonId,
  ) async {
    try {
      final response = await _remoteDataSource.getLessonContent(lessonId);
      return Right(response.data.toEntity());
    } catch (e) {
      return Left(mapFailure(e));
    }
  }
}
