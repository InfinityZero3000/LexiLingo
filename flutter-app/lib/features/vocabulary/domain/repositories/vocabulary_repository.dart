import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';

/// Vocabulary Repository Interface (Domain Layer)
/// Clean Architecture: Domain layer defines contracts
/// Data layer implements these contracts
abstract class VocabularyRepository {
  /// Get vocabulary items (master list)
  Future<Either<Failure, List<VocabularyItemEntity>>> getVocabularyItems({
    String? courseId,
    String? lessonId,
    String? difficultyLevel,
    String? search,
    int limit = 50,
    int offset = 0,
  });

  /// Get vocabulary item by ID
  Future<Either<Failure, VocabularyItemEntity>> getVocabularyItem(
    String vocabularyId,
  );

  /// Get user's vocabulary collection
  Future<Either<Failure, List<UserVocabularyEntity>>> getUserCollection({
    VocabularyStatus? status,
    int limit = 50,
    int offset = 0,
  });

  /// Add vocabulary to user's collection
  Future<Either<Failure, UserVocabularyEntity>> addToCollection(
    String vocabularyId,
  );

  /// Get due vocabulary for review
  Future<Either<Failure, List<UserVocabularyEntity>>> getDueVocabulary({
    int limit = 20,
  });

  /// Submit vocabulary review
  Future<Either<Failure, ReviewResultEntity>> submitReview(
    String userVocabularyId,
    ReviewQuality quality, {
    int? timeSpentMs,
  });

  /// Get vocabulary statistics
  Future<Either<Failure, Map<String, dynamic>>> getVocabularyStats();
}
