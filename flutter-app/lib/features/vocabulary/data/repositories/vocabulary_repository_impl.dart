import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocabulary_remote_datasource.dart';

/// Vocabulary Repository Implementation (Data Layer)
/// Implements the domain repository interface
/// Converts exceptions to failures (Either pattern)
class VocabularyRepositoryImpl implements VocabularyRepository {
  final VocabularyRemoteDataSource remoteDataSource;

  VocabularyRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, List<VocabularyItemEntity>>> getVocabularyItems({
    String? courseId,
    String? lessonId,
    String? difficultyLevel,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final models = await remoteDataSource.getVocabularyItems(
        courseId: courseId,
        lessonId: lessonId,
        difficultyLevel: difficultyLevel,
        search: search,
        limit: limit,
        offset: offset,
      );
      
      // Convert models to entities
      final entities = models.map((model) => model.toEntity()).toList();
      return Right(entities);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, VocabularyItemEntity>> getVocabularyItem(
    String vocabularyId,
  ) async {
    try {
      final model = await remoteDataSource.getVocabularyItem(vocabularyId);
      return Right(model.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getUserCollection({
    VocabularyStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final statusString = status != null 
          ? status.toString().split('.').last 
          : null;
      
      final models = await remoteDataSource.getUserCollection(
        status: statusString,
        limit: limit,
        offset: offset,
      );
      
      final entities = models.map((model) => model.toEntity()).toList();
      return Right(entities);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, UserVocabularyEntity>> addToCollection(
    String vocabularyId,
  ) async {
    try {
      final model = await remoteDataSource.addToCollection(vocabularyId);
      return Right(model.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getDueVocabulary({
    int limit = 20,
  }) async {
    try {
      final models = await remoteDataSource.getDueVocabulary(limit: limit);
      final entities = models.map((model) => model.toEntity()).toList();
      return Right(entities);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, ReviewResultEntity>> submitReview(
    String userVocabularyId,
    ReviewQuality quality, {
    int? timeSpentMs,
  }) async {
    try {
      final model = await remoteDataSource.submitReview(
        userVocabularyId,
        quality.value,
        timeSpentMs: timeSpentMs,
      );
      return Right(model.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getVocabularyStats() async {
    try {
      final stats = await remoteDataSource.getVocabularyStats();
      return Right(stats);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }
}
