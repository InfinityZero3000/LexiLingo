import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/data/datasources/progress_remote_datasource.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

/// Progress Repository Implementation
class ProgressRepositoryImpl implements ProgressRepository {
  final ProgressRemoteDataSource remoteDataSource;

  ProgressRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, ProgressStatsEntity>> getMyProgress() async {
    try {
      final result = await remoteDataSource.getMyProgress();
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, CourseProgressWithUnits>> getCourseProgress(
    String courseId,
  ) async {
    try {
      final result = await remoteDataSource.getCourseProgress(courseId);
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, LessonCompletionResult>> completeLesson({
    required String lessonId,
    required double score,
  }) async {
    try {
      final result = await remoteDataSource.completeLesson(
        lessonId: lessonId,
        score: score,
      );
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, int>> getTotalXp() async {
    try {
      final result = await remoteDataSource.getTotalXp();
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }
}
