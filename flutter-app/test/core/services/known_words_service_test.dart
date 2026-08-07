import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/known_words_service.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/pronunciation_evaluation_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

class _FakeVocabularyRepository implements VocabularyRepository {
  List<UserVocabularyEntity> collection = const [];
  int getUserCollectionCalls = 0;
  Object? failure;

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getUserCollection({
    VocabularyStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    getUserCollectionCalls += 1;
    if (failure != null) return Left(failure as Failure);
    return Right(collection);
  }

  @override
  Future<Either<Failure, List<VocabularyItemEntity>>> getVocabularyItems({
    String? courseId,
    String? lessonId,
    String? difficultyLevel,
    String? tag,
    String? search,
    int limit = 50,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, VocabularyItemEntity>> getVocabularyItem(
    String vocabularyId,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, UserVocabularyEntity>> addToCollection(
    String vocabularyId,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getDueVocabulary({
    int limit = 20,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, ReviewResultEntity>> submitReview(
    String userVocabularyId,
    ReviewQuality quality, {
    int? timeSpentMs,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, PronunciationEvaluationEntity>>
  evaluatePronunciation({
    required String vocabularyId,
    required Uint8List audioData,
    required String filename,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Map<String, dynamic>>> getVocabularyStats() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getDeckItems(
    String deckId,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, VocabularyItemEntity>> getWordOfDay() =>
      throw UnimplementedError();
}

UserVocabularyEntity _entry(String word) => UserVocabularyEntity(
  id: 'id-$word',
  userId: 'user-1',
  vocabularyId: 'vocab-$word',
  status: VocabularyStatus.learning,
  nextReviewDate: DateTime(2026, 1, 1),
  addedAt: DateTime(2026, 1, 1),
  word: word,
);

void main() {
  group('KnownWordsService', () {
    test('lowercases and caches words from the user collection', () async {
      final repo = _FakeVocabularyRepository()
        ..collection = [_entry('Apple'), _entry('Banana')];
      final service = KnownWordsService(vocabularyRepository: repo);

      final first = await service.getKnownWords();
      final second = await service.getKnownWords();

      expect(first, {'apple', 'banana'});
      expect(second, {'apple', 'banana'});
      // Second call must be served from cache, not a second network call.
      expect(repo.getUserCollectionCalls, 1);
    });

    test('forceRefresh bypasses the cache', () async {
      final repo = _FakeVocabularyRepository()..collection = [_entry('cat')];
      final service = KnownWordsService(vocabularyRepository: repo);
      await service.getKnownWords();

      repo.collection = [_entry('cat'), _entry('dog')];
      final refreshed = await service.getKnownWords(forceRefresh: true);

      expect(refreshed, {'cat', 'dog'});
      expect(repo.getUserCollectionCalls, 2);
    });

    test('falls back to the last known cache on repository failure', () async {
      final repo = _FakeVocabularyRepository()..collection = [_entry('cat')];
      final service = KnownWordsService(vocabularyRepository: repo);
      await service.getKnownWords();

      repo.failure = ServerFailure('boom');
      final result = await service.getKnownWords(forceRefresh: true);

      expect(result, {'cat'});
    });

    test('addKnownWord makes a word known immediately without a refetch', () async {
      final repo = _FakeVocabularyRepository();
      final service = KnownWordsService(vocabularyRepository: repo);
      await service.getKnownWords();
      expect(await service.getKnownWords(), isEmpty);

      // This is what the QuickSaveVocabularyService stream subscription
      // calls internally the moment a word is saved anywhere in the app.
      service.addKnownWord('Elephant');

      expect(await service.getKnownWords(), {'elephant'});
      expect(repo.getUserCollectionCalls, 1);
    });
  });
}
