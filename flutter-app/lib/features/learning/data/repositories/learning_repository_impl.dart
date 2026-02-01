import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/features/learning/data/datasources/learning_remote_datasource.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_attempt_model.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/data/models/answer_response_model.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_complete_model.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

/// Implementation of LearningRepository
class LearningRepositoryImpl implements LearningRepository {
  final LearningRemoteDataSource _remoteDataSource;

  LearningRepositoryImpl({
    required LearningRemoteDataSource remoteDataSource,
  }) : _remoteDataSource = remoteDataSource;

  @override
  Future<Either<Failure, LessonAttemptModel>> startLesson(String lessonId) async {
    try {
      final response = await _remoteDataSource.startLesson(lessonId);
      return Right(response.data);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AnswerResponseModel>> submitAnswer({
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
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, LessonCompleteModel>> completeLesson(String attemptId) async {
    try {
      final response = await _remoteDataSource.completeLesson(attemptId);
      return Right(response.data);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, CourseRoadmapModel>> getCourseRoadmap(String courseId) async {
    try {
      final response = await _remoteDataSource.getCourseRoadmap(courseId);
      return Right(response.data);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, LessonEntity>> getLessonContent(String lessonId) async {
    try {
      final response = await _remoteDataSource.getLessonContent(lessonId);
      return Right(response.data.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
