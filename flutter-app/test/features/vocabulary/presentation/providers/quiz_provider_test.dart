import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/quiz_question_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_due_vocabulary_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/submit_review_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/quiz_provider.dart';

VocabularyItemEntity _item(String id, String word, String definition) =>
    VocabularyItemEntity(
      id: id,
      word: word,
      definition: definition,
      partOfSpeech: 'noun',
      difficultyLevel: 'B1',
      createdAt: DateTime.utc(2026, 6, 8),
    );

UserVocabularyEntity _userVocab(String id, String vocabId) =>
    UserVocabularyEntity(
      id: id,
      userId: 'user-1',
      vocabularyId: vocabId,
      status: VocabularyStatus.reviewing,
      nextReviewDate: DateTime.utc(2026, 6, 8),
      addedAt: DateTime.utc(2026, 6, 1),
    );

class _FakeQuizRepository extends Fake implements VocabularyRepository {
  final List<UserVocabularyEntity> due;
  final Map<String, VocabularyItemEntity> items;
  final List<VocabularyItemEntity> pool;

  /// Records each submitted review as (userVocabularyId, quality).
  final List<(String, ReviewQuality)> submissions = [];

  _FakeQuizRepository({
    required this.due,
    required this.items,
    required this.pool,
  });

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getDueVocabulary({
    int limit = 20,
  }) async =>
      Right(due);

  @override
  Future<Either<Failure, VocabularyItemEntity>> getVocabularyItem(
    String vocabularyId,
  ) async {
    final item = items[vocabularyId];
    return item == null
        ? const Left(NotFoundFailure())
        : Right(item);
  }

  List<UserVocabularyEntity> deckItems = [];
  List<UserVocabularyEntity> collection = [];
  final List<String> addedToCollection = [];

  @override
  Future<Either<Failure, List<VocabularyItemEntity>>> getVocabularyItems({
    String? courseId,
    String? lessonId,
    String? difficultyLevel,
    String? tag,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async =>
      Right(pool);

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getDeckItems(
    String deckId,
  ) async =>
      Right(deckItems);

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getUserCollection({
    VocabularyStatus? status,
    int limit = 50,
    int offset = 0,
  }) async =>
      Right(collection);

  @override
  Future<Either<Failure, UserVocabularyEntity>> addToCollection(
    String vocabularyId,
  ) async {
    addedToCollection.add(vocabularyId);
    return Right(_userVocab('uv-$vocabularyId', vocabularyId));
  }

  @override
  Future<Either<Failure, ReviewResultEntity>> submitReview(
    String userVocabularyId,
    ReviewQuality quality, {
    int? timeSpentMs,
  }) async {
    submissions.add((userVocabularyId, quality));
    return Right(
      ReviewResultEntity(
        userVocabularyId: userVocabularyId,
        quality: quality,
        xpEarned: 10,
        newEaseFactor: 2.5,
        newInterval: 3,
        newRepetitions: 2,
        nextReviewDate: DateTime.utc(2026, 6, 11),
        reviewedAt: DateTime.utc(2026, 6, 8),
      ),
    );
  }
}

QuizProvider _build(_FakeQuizRepository repo) => QuizProvider(
      getDueVocabularyUseCase: GetDueVocabularyUseCase(repo),
      submitReviewUseCase: SubmitReviewUseCase(repo),
      vocabularyRepository: repo,
    );

void main() {
  group('QuizProvider', () {
    late _FakeQuizRepository repo;

    setUp(() {
      final w1 = _item('v1', 'serene', 'calm, peaceful, and untroubled');
      final w2 = _item('v2', 'candid', 'truthful and straightforward');
      final fillers = [
        _item('v3', 'lucid', 'expressed clearly; easy to understand'),
        _item('v4', 'frugal', 'sparing or economical with money'),
        _item('v5', 'vivid', 'producing powerful, clear images'),
      ];
      repo = _FakeQuizRepository(
        due: [_userVocab('uv1', 'v1'), _userVocab('uv2', 'v2')],
        items: {'v1': w1, 'v2': w2},
        pool: [w1, w2, ...fillers],
      );
    });

    test('generates two-directional questions for each due word', () async {
      final provider = _build(repo);
      await provider.startQuizSession();

      expect(provider.errorMessage, isNull);
      // 2 words × 2 directions
      expect(provider.totalQuestions, 4);

      final directions = <QuizDirection>{};
      final wordIds = <String>{};
      while (provider.currentQuestion != null) {
        final q = provider.currentQuestion!;
        directions.add(q.direction);
        wordIds.add(q.card.userVocabulary.id);
        expect(q.options.length, greaterThanOrEqualTo(2));
        expect(q.options.where((o) => o.isCorrect).length, 1);
        provider.answer(q.correctIndex!);
        provider.next();
      }
      await provider.finishPending();

      expect(directions, {
        QuizDirection.termToMeaning,
        QuizDirection.meaningToTerm,
      });
      expect(wordIds, {'uv1', 'uv2'});
      provider.dispose();
    });

    test('correct answers map a word to easy quality and award XP', () async {
      final provider = _build(repo);
      await provider.startQuizSession();

      while (provider.currentQuestion != null) {
        final correct = provider.currentQuestion!.correctIndex!;
        provider.answer(correct);
        provider.next();
      }
      await provider.finishPending();

      // One review submitted per word, both fully correct → easy(4)
      expect(repo.submissions.length, 2);
      expect(
        repo.submissions.map((s) => s.$2).toList(),
        everyElement(ReviewQuality.easy),
      );
      expect(provider.totalXpEarned, 20);
      expect(provider.wordsMastered, 2);
      provider.dispose();
    });

    test('a partially-correct word maps to good quality', () async {
      final provider = _build(repo);
      await provider.startQuizSession();

      var wrongedUv2 = false;
      while (provider.currentQuestion != null) {
        final q = provider.currentQuestion!;
        final correct = q.correctIndex!;
        final isUv2 = q.card.userVocabulary.id == 'uv2';
        if (isUv2 && !wrongedUv2) {
          wrongedUv2 = true;
          provider.answer((correct + 1) % q.options.length); // wrong
        } else {
          provider.answer(correct);
        }
        provider.next();
      }
      await provider.finishPending();

      final byWord = {for (final s in repo.submissions) s.$1: s.$2};
      expect(byWord['uv1'], ReviewQuality.easy);
      expect(byWord['uv2'], ReviewQuality.good);
      expect(provider.wordsMastered, 1);
      provider.dispose();
    });

    test('deck session builds a quiz from deck items', () async {
      repo.deckItems = [_userVocab('uv1', 'v1'), _userVocab('uv2', 'v2')];
      final provider = _build(repo);
      await provider.startDeckSession(deckId: 'deck-1');

      expect(provider.errorMessage, isNull);
      expect(provider.totalQuestions, 4);
      provider.dispose();
    });

    test('topic session adds uncollected words then quizzes them', () async {
      // 'v1' already in collection; 'v2' must be added on the fly.
      repo.collection = [_userVocab('uv1', 'v1')];
      final provider = _build(repo);
      await provider.startTopicSession(tag: 'general');

      expect(provider.errorMessage, isNull);
      expect(repo.addedToCollection, contains('v2'));
      expect(provider.hasSession, isTrue);
      provider.dispose();
    });

    test('surfaces an error when no words are due', () async {
      final emptyRepo = _FakeQuizRepository(due: [], items: {}, pool: []);
      final provider = _build(emptyRepo);
      await provider.startQuizSession();

      expect(provider.hasSession, isFalse);
      expect(provider.errorMessage, isNotNull);
      provider.dispose();
    });
  });
}
