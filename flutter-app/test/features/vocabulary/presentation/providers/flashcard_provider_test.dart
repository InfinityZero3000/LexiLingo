import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_due_vocabulary_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/submit_review_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';

class _RecordingVocabularyRepository extends Fake
    implements VocabularyRepository {
  int? requestedCollectionLimit;
  List<UserVocabularyEntity> due = const [];
  bool failDueLookup = false;
  Completer<void>? submitGate;
  int failSubmits = 0;
  final missingItems = <String>{};
  Completer<void>? itemGate;
  final sent = <String>[];

  final vocabularyItem = VocabularyItemEntity(
    id: 'vocabulary-1',
    word: 'discover',
    definition: 'to find something for the first time',
    partOfSpeech: 'verb',
    difficultyLevel: 'A2',
    createdAt: DateTime.utc(2026, 6, 8),
  );

  final userVocabulary = UserVocabularyEntity(
    id: 'user-vocabulary-1',
    userId: 'user-1',
    vocabularyId: 'vocabulary-1',
    status: VocabularyStatus.learning,
    nextReviewDate: DateTime.utc(2026, 6, 9),
    addedAt: DateTime.utc(2026, 6, 8),
  );

  @override
  Future<Either<Failure, List<VocabularyItemEntity>>> getVocabularyItems({
    String? courseId,
    String? lessonId,
    String? difficultyLevel,
    String? tag,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    return Right([vocabularyItem]);
  }

  @override
  Future<Either<Failure, VocabularyItemEntity>> getVocabularyItem(
    String id,
  ) async {
    await itemGate?.future;
    return missingItems.contains(id)
        ? const Left(ServerFailure('gone'))
        : Right(vocabularyItem);
  }

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getDueVocabulary({
    int limit = 20,
  }) async {
    if (failDueLookup) throw StateError('socket closed: 10.0.0.5:8000');
    return Right(due);
  }

  @override
  Future<Either<Failure, ReviewResultEntity>> submitReview(
    String userVocabularyId,
    ReviewQuality quality, {
    int? timeSpentMs,
  }) async {
    await submitGate?.future;
    if (failSubmits > 0) {
      failSubmits--;
      return const Left(ServerFailure('offline'));
    }
    sent.add(userVocabularyId);
    return Right(
      ReviewResultEntity(
        userVocabularyId: userVocabularyId,
        quality: quality,
        xpEarned: 5,
        newEaseFactor: 2.5,
        newInterval: 1,
        newRepetitions: 1,
        nextReviewDate: DateTime.utc(2026, 6, 10),
        reviewedAt: DateTime.utc(2026, 6, 9),
      ),
    );
  }

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getUserCollection({
    VocabularyStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    requestedCollectionLimit = limit;
    return Right([userVocabulary]);
  }
}

void main() {
  test(
    'topic session uses the production-compatible collection limit',
    () async {
      final repository = _RecordingVocabularyRepository();
      final provider = FlashcardProvider(
        getDueVocabularyUseCase: GetDueVocabularyUseCase(repository),
        submitReviewUseCase: SubmitReviewUseCase(repository),
        vocabularyRepository: repository,
      );

      await provider.startTopicSession(tag: 'general');

      expect(repository.requestedCollectionLimit, 100);
      expect(provider.errorMessage, isNull);
      expect(provider.currentSession?.totalCards, 1);

      provider.dispose();
    },
  );

  test('no words due is an empty state, not an error', () async {
    final repository = _RecordingVocabularyRepository();
    final provider = FlashcardProvider(
      getDueVocabularyUseCase: GetDueVocabularyUseCase(repository),
      submitReviewUseCase: SubmitReviewUseCase(repository),
      vocabularyRepository: repository,
    );

    await provider.startReviewSession();

    expect(provider.nothingDue, isTrue);
    expect(provider.errorMessage, isNull);
    expect(provider.hasSession, isFalse);
    expect(provider.isLoading, isFalse);

    repository.due = [repository.userVocabulary];
    await provider.startReviewSession();

    expect(provider.nothingDue, isFalse);
    expect(provider.currentSession?.totalCards, 1);

    provider.dispose();
  });

  test(
    'an unexpected failure never leaks its details to the learner',
    () async {
      final repository = _RecordingVocabularyRepository()..failDueLookup = true;
      final provider = FlashcardProvider(
        getDueVocabularyUseCase: GetDueVocabularyUseCase(repository),
        submitReviewUseCase: SubmitReviewUseCase(repository),
        vocabularyRepository: repository,
      );

      await provider.startReviewSession();

      expect(provider.errorMessage, 'flashcard.unexpectedError');
      expect(provider.errorMessage, isNot(contains('socket')));
      expect(provider.nothingDue, isFalse);

      provider.dispose();
    },
  );

  group('rating a card', () {
    UserVocabularyEntity due(String id, {String? word}) => UserVocabularyEntity(
      id: id,
      userId: 'user-1',
      vocabularyId: word ?? 'vocabulary-1',
      status: VocabularyStatus.learning,
      nextReviewDate: DateTime.utc(2026, 6, 9),
      addedAt: DateTime.utc(2026, 6, 8),
    );

    FlashcardProvider build(_RecordingVocabularyRepository repository) =>
        FlashcardProvider(
          getDueVocabularyUseCase: GetDueVocabularyUseCase(repository),
          submitReviewUseCase: SubmitReviewUseCase(repository),
          vocabularyRepository: repository,
        );

    test('shows the next card before the server has answered', () async {
      final repository = _RecordingVocabularyRepository()
        ..due = [due('a'), due('b'), due('c')]
        ..submitGate = Completer<void>();
      final provider = build(repository);
      await provider.startReviewSession();

      await provider.submitReview(ReviewQuality.good);

      expect(provider.currentSession!.reviewedCards, 1);
      expect(provider.currentSession!.currentCard!.userVocabulary.id, 'b');
      expect(provider.isCardFlipped, isFalse);
      expect(repository.sent, isEmpty);

      repository.submitGate!.complete();
      await provider.submitReview(ReviewQuality.good);
      await provider.submitReview(ReviewQuality.good);

      expect(repository.sent, ['a', 'b', 'c']);
      expect(provider.currentSession!.totalXpEarned, 15);
      expect(provider.currentSession!.completedAt, isNotNull);
      provider.dispose();
    });

    test(
      'the last card waits for delivery so the summary has its XP',
      () async {
        final repository = _RecordingVocabularyRepository()..due = [due('a')];
        final provider = build(repository);
        await provider.startReviewSession();

        await provider.submitReview(ReviewQuality.easy);

        expect(repository.sent, ['a']);
        expect(provider.currentSession!.totalXpEarned, 5);
        provider.dispose();
      },
    );

    test('a rating that failed is sent again with the next one', () async {
      final repository = _RecordingVocabularyRepository()
        ..due = [due('a'), due('b')]
        ..failSubmits = 1;
      final provider = build(repository);
      await provider.startReviewSession();

      await provider.submitReview(ReviewQuality.good);
      await provider.submitReview(ReviewQuality.good);

      expect(repository.sent, ['a', 'b']);
      provider.dispose();
    });

    test(
      'ratings still queued at sign-out are never sent as the next account',
      () async {
        final repository = _RecordingVocabularyRepository()
          ..due = [due('a'), due('b'), due('c')]
          ..submitGate = Completer<void>();
        final provider = build(repository);
        await provider.startReviewSession();
        await provider.submitReview(ReviewQuality.good); // a: on its way
        await provider.submitReview(ReviewQuality.good); // b: waits behind a

        provider.reset();
        repository
          ..due = [due('x')]
          ..failSubmits = 0;
        repository.submitGate!.complete();
        await provider.startReviewSession();
        await provider.submitReview(ReviewQuality.good);

        expect(repository.sent, isNot(contains('b')));
        expect(repository.sent, isNot(contains('c')));
        expect(repository.sent.last, 'x');
        provider.dispose();
      },
    );

    test('a rating that fails after sign-out is not retried for the next '
        'account', () async {
      final repository = _RecordingVocabularyRepository()
        ..due = [due('a'), due('b')]
        ..submitGate = Completer<void>()
        ..failSubmits = 1;
      final provider = build(repository);
      await provider.startReviewSession();
      await provider.submitReview(ReviewQuality.good); // a: will fail

      provider.reset();
      repository.submitGate!.complete();
      repository.due = [due('x')];
      await provider.startReviewSession();
      await provider.submitReview(ReviewQuality.good);

      expect(repository.sent, ['x'], reason: 'a must not be re-queued');
      provider.dispose();
    });

    test(
      'flushDelivery lets a rating on its way arrive, within a bound',
      () async {
        final repository = _RecordingVocabularyRepository()
          ..due = [due('a'), due('b')]
          ..submitGate = Completer<void>();
        final provider = build(repository);
        await provider.startReviewSession();
        await provider.submitReview(ReviewQuality.good);

        final slow = provider.flushDelivery(
          timeout: const Duration(milliseconds: 20),
        );
        await slow;
        expect(repository.sent, isEmpty, reason: 'bounded: it gave up waiting');

        final flushed = provider.flushDelivery();
        repository.submitGate!.complete();
        await flushed;
        expect(repository.sent, ['a']);
        provider.dispose();
      },
    );

    test('ratings still unsent when the wait runs out are cancelled', () async {
      final repository = _RecordingVocabularyRepository()
        ..due = [due('a'), due('b'), due('c')]
        ..submitGate = Completer<void>();
      final provider = build(repository);
      await provider.startReviewSession();
      await provider.submitReview(ReviewQuality.good); // a: in flight
      await provider.submitReview(ReviewQuality.good); // b: queued behind

      await provider.flushDelivery(timeout: const Duration(milliseconds: 20));
      repository.submitGate!.complete();
      await pumpEventQueue();

      expect(repository.sent, ['a'], reason: 'b is never sent');
      provider.dispose();
    });

    test('a word that cannot be loaded does not strand the session', () async {
      final repository = _RecordingVocabularyRepository()
        ..missingItems.add('gone')
        ..due = [due('a'), due('b', word: 'gone'), due('c')];
      final provider = build(repository);
      await provider.startReviewSession();

      expect(provider.currentSession!.cards.length, 2);
      expect(provider.currentSession!.totalCards, 2);

      await provider.submitReview(ReviewQuality.good);
      await provider.submitReview(ReviewQuality.good);

      expect(provider.currentSession!.isCompleted, isTrue);
      expect(provider.currentSession!.completedAt, isNotNull);
      provider.dispose();
    });

    test('leaving mid-delivery does not notify a disposed provider', () async {
      final repository = _RecordingVocabularyRepository()
        ..due = [due('a'), due('b')]
        ..submitGate = Completer<void>();
      final provider = build(repository);
      await provider.startReviewSession();

      await provider.submitReview(ReviewQuality.good);
      provider.dispose();
      repository.submitGate!.complete();
      await Future<void>.delayed(Duration.zero);

      expect(repository.sent, ['a']);
    });
  });

  test('a batch that lands after the session ended is not appended to the '
      'next one', () async {
    final repository = _RecordingVocabularyRepository();
    repository.due = [
      for (var i = 0; i < 12; i++)
        UserVocabularyEntity(
          id: 'uv-$i',
          userId: 'user-1',
          vocabularyId: 'vocabulary-1',
          status: VocabularyStatus.learning,
          nextReviewDate: DateTime.utc(2026, 6, 9),
          addedAt: DateTime.utc(2026, 6, 8),
        ),
    ];
    final provider = FlashcardProvider(
      getDueVocabularyUseCase: GetDueVocabularyUseCase(repository),
      submitReviewUseCase: SubmitReviewUseCase(repository),
      vocabularyRepository: repository,
    );

    await provider.startReviewSession();
    expect(provider.currentSession!.cards.length, 10);

    final gate = Completer<void>();
    repository.itemGate = gate;
    for (var i = 0; i < 5; i++) {
      await provider.submitReview(ReviewQuality.good);
    }
    provider.endSession();
    repository.itemGate = null;
    await provider.startReviewSession();
    expect(provider.currentSession!.cards.length, 10);

    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(provider.currentSession!.cards.length, 10);
    expect(provider.currentSession!.totalCards, 12);
    provider.dispose();
  });
}
