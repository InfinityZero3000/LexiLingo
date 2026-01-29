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
    // TODO: Implement when lesson content API is available
    // For now, return mock lesson for testing
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      final lesson = _createMockLesson(lessonId);
      return Right(lesson);
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  /// Create mock lesson for testing (temporary until API is ready)
  LessonEntity _createMockLesson(String lessonId) {
    return LessonEntity(
      id: lessonId,
      title: 'Introduction to Greetings',
      description: 'Learn basic greeting phrases',
      orderIndex: 0,
      exercises: [
        Exercise(
          id: '1',
          type: ExerciseType.multipleChoice,
          question: 'What is the correct way to say "Hello" in formal English?',
          options: [
            'Hey!',
            'Good morning',
            'Yo!',
            'What\'s up?',
          ],
          correctAnswer: 'Good morning',
          explanation: '"Good morning" is the most formal greeting among these options.',
          hint: 'Think about what you would say in a professional setting.',
        ),
        Exercise(
          id: '2',
          type: ExerciseType.trueFalse,
          question: '"How are you?" is an appropriate greeting in business contexts.',
          options: ['True', 'False'],
          correctAnswer: 'True',
          explanation: 'This is a polite and common greeting in professional settings.',
        ),
        Exercise(
          id: '3',
          type: ExerciseType.fillInBlank,
          question: 'Complete: "Nice to ___ you."',
          correctAnswer: 'meet',
          explanation: '"Nice to meet you" is a common greeting when meeting someone for the first time.',
          hint: 'This word is used when encountering someone for the first time.',
        ),
        Exercise(
          id: '4',
          type: ExerciseType.translate,
          question: 'Translate to English: "Enchanté" (French)',
          correctAnswer: 'Nice to meet you',
          explanation: '"Enchanté" is French for "Nice to meet you" or "Pleased to meet you".',
          hint: 'This is a polite greeting when meeting someone new.',
        ),
      ],
      estimatedMinutes: 10,
      xpReward: 50,
    );
  }
}
