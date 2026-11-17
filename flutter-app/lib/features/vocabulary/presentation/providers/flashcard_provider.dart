import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_due_vocabulary_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/submit_review_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// Flashcard Provider (Presentation Layer)
/// Manages flashcard review session state
/// Clean Architecture: Presentation layer orchestrates use cases
class FlashcardProvider extends ChangeNotifier {
  static const int _collectionCompatibilityPageSize = 100;
  static const int _initialBatchSize = 10;
  static const int _batchSize = 10;
  // Trigger background preload when this many loaded cards remain unreviewed
  static const int _preloadThreshold = 5;

  final GetDueVocabularyUseCase getDueVocabularyUseCase;
  final SubmitReviewUseCase submitReviewUseCase;
  final VocabularyRepository vocabularyRepository;

  FlashcardProvider({
    required this.getDueVocabularyUseCase,
    required this.submitReviewUseCase,
    required this.vocabularyRepository,
  });

  // Session state
  ReviewSessionEntity? _currentSession;
  bool _isLoading = false;
  UiText? _errorMessage;
  bool _nothingDue = false;
  bool _isCardFlipped = false;
  DateTime? _cardStartTime;

  // Lazy loading state (review / deck sessions)
  List<UserVocabularyEntity> _pendingUserVocabs = [];
  int _loadedVocabCount = 0;
  bool _isLoadingMore = false;

  // Ratings are delivered in the background, one after another
  Future<void> _delivery = Future<void>.value();
  final List<SubmitReviewParams> _unsent = [];
  bool _disposed = false;

  // Getters
  ReviewSessionEntity? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage?.resolve();
  bool get nothingDue => _nothingDue;
  bool get isCardFlipped => _isCardFlipped;
  bool get hasSession => _currentSession != null;
  bool get isLoadingMore => _isLoadingMore;
  int get dueCount => _currentSession?.remainingCards ?? 0;

  void _resetLazyState() {
    _pendingUserVocabs = [];
    _loadedVocabCount = 0;
    _isLoadingMore = false;
  }

  /// Fetch vocabulary item details in parallel for a batch of user vocabs
  Future<List<ReviewCardEntity>> _loadVocabCards(
    List<UserVocabularyEntity> userVocabs,
  ) async {
    final futures = userVocabs.map((userVocab) async {
      final result = await vocabularyRepository.getVocabularyItem(
        userVocab.vocabularyId,
      );
      return result.fold<ReviewCardEntity?>(
        (failure) {
          debugPrint('Failed to load vocabulary: ${userVocab.vocabularyId}');
          return null;
        },
        (vocabItem) => ReviewCardEntity(
          userVocabulary: userVocab,
          vocabularyItem: vocabItem,
        ),
      );
    });
    final results = await Future.wait(futures);
    return results.whereType<ReviewCardEntity>().toList();
  }

  /// Background preload of the next batch — silently appends to session cards
  Future<void> _loadMoreCards() async {
    if (_isLoadingMore) return;
    if (_loadedVocabCount >= _pendingUserVocabs.length) return;

    _isLoadingMore = true;

    try {
      final nextBatch = _pendingUserVocabs
          .skip(_loadedVocabCount)
          .take(_batchSize)
          .toList();

      final newCards = await _loadVocabCards(nextBatch);
      _loadedVocabCount += nextBatch.length;

      final dropped = nextBatch.length - newCards.length;
      final session = _currentSession;
      if (session != null && (newCards.isNotEmpty || dropped > 0)) {
        _currentSession = session.copyWith(
          cards: [...session.cards, ...newCards],
          totalCards: session.totalCards - dropped,
        );
        _notify();
      }
    } catch (e) {
      debugPrint('Error preloading cards: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Start a new review session with lazy loading
  Future<void> startReviewSession({int limit = 50}) async {
    _resetLazyState();
    _isLoading = true;
    _errorMessage = null;
    _nothingDue = false;
    notifyListeners();

    try {
      final result = await getDueVocabularyUseCase(
        GetDueVocabularyParams(limit: limit),
      );

      await result.fold(
        (failure) async {
          _errorMessage = (_getFailureMessage(failure));
          _isLoading = false;
          notifyListeners();
        },
        (dueVocabularyList) async {
          if (dueVocabularyList.isEmpty) {
            _nothingDue = true;
            _isLoading = false;
            notifyListeners();
            return;
          }

          _pendingUserVocabs = dueVocabularyList;

          // Load first batch in parallel — fast initial display
          final firstBatch = _pendingUserVocabs
              .take(_initialBatchSize)
              .toList();
          final cards = await _loadVocabCards(firstBatch);
          _loadedVocabCount = firstBatch.length;

          if (cards.isEmpty) {
            _errorMessage = UiText.key('flashcard.loadFailed');
            _isLoading = false;
            notifyListeners();
            return;
          }

          _currentSession = ReviewSessionEntity(
            cards: cards,
            startedAt: DateTime.now(),
            totalCards:
                _pendingUserVocabs.length - (firstBatch.length - cards.length),
          );

          _cardStartTime = DateTime.now();
          _isLoading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Unexpected vocabulary error: $e');
      _errorMessage = UiText.key('flashcard.unexpectedError');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Start a new review session for a specific topic (tag)
  Future<void> startTopicSession({required String tag, int limit = 20}) async {
    _resetLazyState();
    _isLoading = true;
    _errorMessage = null;
    _currentSession = null;
    notifyListeners();

    try {
      final itemsResult = await vocabularyRepository.getVocabularyItems(
        tag: tag,
        limit: limit,
      );

      await itemsResult.fold(
        (failure) async {
          _errorMessage = (_getFailureMessage(failure));
          _isLoading = false;
          notifyListeners();
        },
        (vocabItems) async {
          if (vocabItems.isEmpty) {
            _errorMessage = UiText.key(
              'flashcard.noVocabularyForTopic',
              namedArgs: {'topic': tag},
            );
            _isLoading = false;
            notifyListeners();
            return;
          }

          final collectionResult = await vocabularyRepository.getUserCollection(
            limit: _collectionCompatibilityPageSize,
          );

          await collectionResult.fold(
            (failure) async {
              _errorMessage = (_getFailureMessage(failure));
              _isLoading = false;
              notifyListeners();
            },
            (userCollection) async {
              final collectionMap = {
                for (var uc in userCollection) uc.vocabularyId: uc,
              };

              // Parallelize addToCollection calls for items not yet in collection
              final cardFutures = vocabItems.map((item) async {
                var userVocab = collectionMap[item.id];
                if (userVocab == null) {
                  final addResult = await vocabularyRepository.addToCollection(
                    item.id,
                  );
                  addResult.fold(
                    (failure) => debugPrint(
                      'Failed to auto-add item to collection: ${item.id}',
                    ),
                    (added) => userVocab = added,
                  );
                }
                if (userVocab == null) return null;
                return ReviewCardEntity(
                  userVocabulary: userVocab!,
                  vocabularyItem: item,
                );
              });

              final results = await Future.wait(cardFutures);
              final cards = results.whereType<ReviewCardEntity>().toList();

              if (cards.isEmpty) {
                _errorMessage = UiText.key('flashcard.prepareFailed');
                _isLoading = false;
                notifyListeners();
                return;
              }

              _currentSession = ReviewSessionEntity(
                cards: cards,
                startedAt: DateTime.now(),
                totalCards: cards.length,
              );

              _cardStartTime = DateTime.now();
              _isLoading = false;
              _isCardFlipped = false;
              notifyListeners();
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Unexpected vocabulary error: $e');
      _errorMessage = UiText.key('flashcard.unexpectedError');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Start a new review session for a custom deck with lazy loading
  Future<void> startDeckSession({
    required String deckId,
    int limit = 50,
  }) async {
    _resetLazyState();
    _isLoading = true;
    _errorMessage = null;
    _currentSession = null;
    notifyListeners();

    try {
      final result = await vocabularyRepository.getDeckItems(deckId);

      await result.fold(
        (failure) async {
          _errorMessage = (_getFailureMessage(failure));
          _isLoading = false;
          notifyListeners();
        },
        (deckItems) async {
          if (deckItems.isEmpty) {
            _errorMessage = UiText.key('flashcard.noVocabularyInDeck');
            _isLoading = false;
            notifyListeners();
            return;
          }

          _pendingUserVocabs = deckItems.take(limit).toList();

          final firstBatch = _pendingUserVocabs
              .take(_initialBatchSize)
              .toList();
          final cards = await _loadVocabCards(firstBatch);
          _loadedVocabCount = firstBatch.length;

          if (cards.isEmpty) {
            _errorMessage = UiText.key('flashcard.loadFailed');
            _isLoading = false;
            notifyListeners();
            return;
          }

          _currentSession = ReviewSessionEntity(
            cards: cards,
            startedAt: DateTime.now(),
            totalCards:
                _pendingUserVocabs.length - (firstBatch.length - cards.length),
          );

          _cardStartTime = DateTime.now();
          _isLoading = false;
          _isCardFlipped = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Unexpected vocabulary error: $e');
      _errorMessage = UiText.key('flashcard.unexpectedError');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Flip current card (front <-> back)
  void flipCard() {
    _isCardFlipped = !_isCardFlipped;
    notifyListeners();
  }

  /// Moves to the next card at once and delivers the rating in the
  /// background, so a slow network never leaves the pile waiting. Only the last
  /// card waits for delivery, so the summary shows the final XP.
  Future<void> submitReview(ReviewQuality quality) async {
    final session = _currentSession;
    final card = session?.currentCard;
    if (session == null || card == null) return;

    final timeSpentMs = _cardStartTime != null
        ? DateTime.now().difference(_cardStartTime!).inMilliseconds
        : null;

    final tags = card.vocabularyItem.tags;
    trackContentInteraction(
      itemType: 'vocab',
      itemId: card.userVocabulary.vocabularyId,
      action: quality.isCorrect ? 'review_correct' : 'review_incorrect',
      topic: (tags != null && tags.isNotEmpty) ? tags.first : null,
      source: 'flashcard',
      dwellMs: timeSpentMs,
    );

    final reviewed = session.reviewedCards + 1;
    _currentSession = session.copyWith(
      reviewedCards: reviewed,
      correctCount: session.correctCount + (quality.isCorrect ? 1 : 0),
    );

    // Trigger background preload when approaching end of loaded cards
    if (_currentSession!.cards.length - reviewed <= _preloadThreshold) {
      _loadMoreCards(); // fire-and-forget
    }

    _isCardFlipped = false;
    _cardStartTime = DateTime.now();
    notifyListeners();

    final review = SubmitReviewParams(
      userVocabularyId: card.userVocabulary.id,
      quality: quality,
      timeSpentMs: timeSpentMs,
    );
    _delivery = _delivery.then((_) => _deliver(review));

    if (_currentSession?.isCompleted ?? false) {
      await _delivery;
      final done = _currentSession;
      if (done != null) {
        _currentSession = done.copyWith(completedAt: DateTime.now());
        _notify();
      }
    }
  }

  /// One rating at a time, in order. A rating that fails is retried ahead of
  /// the next one; whatever is still unsent after the last card is dropped
  /// and its word comes due again.
  Future<void> _deliver(SubmitReviewParams review) async {
    _unsent.add(review);
    final batch = List.of(_unsent);
    _unsent.clear();
    for (final item in batch) {
      try {
        final result = await submitReviewUseCase(item);
        result.fold((_) => _unsent.add(item), (reviewResult) {
          final session = _currentSession;
          if (session == null) return;
          _currentSession = session.copyWith(
            totalXpEarned: session.totalXpEarned + reviewResult.xpEarned,
          );
        });
      } catch (e) {
        debugPrint('Failed to submit review: $e');
        _unsent.add(item);
      }
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// End current session
  void endSession() {
    _resetLazyState();
    _currentSession = null;
    _isCardFlipped = false;
    _cardStartTime = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  UiText _getFailureMessage(failure) {
    final message = failure.message as String?;
    return message != null
        ? UiText.raw(message)
        : const UiText.key('flashcard.unexpectedError');
  }

  @override
  void dispose() {
    _disposed = true;
    _currentSession = null;
    super.dispose();
  }
}
