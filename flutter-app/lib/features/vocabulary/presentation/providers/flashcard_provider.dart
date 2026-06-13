import 'package:flutter/foundation.dart';
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
  String? _errorMessage;
  bool _isCardFlipped = false;
  DateTime? _cardStartTime;

  // Lazy loading state (review / deck sessions)
  List<UserVocabularyEntity> _pendingUserVocabs = [];
  int _loadedVocabCount = 0;
  bool _isLoadingMore = false;

  // Getters
  ReviewSessionEntity? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
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

      if (_currentSession != null && newCards.isNotEmpty) {
        _currentSession = _currentSession!.copyWith(
          cards: [..._currentSession!.cards, ...newCards],
        );
        notifyListeners();
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
    notifyListeners();

    try {
      final result = await getDueVocabularyUseCase(
        GetDueVocabularyParams(limit: limit),
      );

      await result.fold(
        (failure) async {
          _errorMessage = _getFailureMessage(failure);
          _isLoading = false;
          notifyListeners();
        },
        (dueVocabularyList) async {
          if (dueVocabularyList.isEmpty) {
            _errorMessage = 'No vocabulary due for review!';
            _isLoading = false;
            notifyListeners();
            return;
          }

          _pendingUserVocabs = dueVocabularyList;

          // Load first batch in parallel — fast initial display
          final firstBatch =
              _pendingUserVocabs.take(_initialBatchSize).toList();
          final cards = await _loadVocabCards(firstBatch);
          _loadedVocabCount = firstBatch.length;

          if (cards.isEmpty) {
            _errorMessage = 'Failed to load vocabulary items';
            _isLoading = false;
            notifyListeners();
            return;
          }

          _currentSession = ReviewSessionEntity(
            cards: cards,
            startedAt: DateTime.now(),
            totalCards: _pendingUserVocabs.length,
          );

          _cardStartTime = DateTime.now();
          _isLoading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
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
          _errorMessage = _getFailureMessage(failure);
          _isLoading = false;
          notifyListeners();
        },
        (vocabItems) async {
          if (vocabItems.isEmpty) {
            _errorMessage = 'No vocabulary found for topic: $tag';
            _isLoading = false;
            notifyListeners();
            return;
          }

          final collectionResult = await vocabularyRepository.getUserCollection(
            limit: _collectionCompatibilityPageSize,
          );

          await collectionResult.fold(
            (failure) async {
              _errorMessage = _getFailureMessage(failure);
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
                _errorMessage =
                    'Failed to prepare vocabulary cards for study.';
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
      _errorMessage = 'Unexpected error: $e';
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
          _errorMessage = _getFailureMessage(failure);
          _isLoading = false;
          notifyListeners();
        },
        (deckItems) async {
          if (deckItems.isEmpty) {
            _errorMessage = 'No vocabulary found in this deck!';
            _isLoading = false;
            notifyListeners();
            return;
          }

          _pendingUserVocabs = deckItems.take(limit).toList();

          final firstBatch =
              _pendingUserVocabs.take(_initialBatchSize).toList();
          final cards = await _loadVocabCards(firstBatch);
          _loadedVocabCount = firstBatch.length;

          if (cards.isEmpty) {
            _errorMessage = 'Failed to load vocabulary items';
            _isLoading = false;
            notifyListeners();
            return;
          }

          _currentSession = ReviewSessionEntity(
            cards: cards,
            startedAt: DateTime.now(),
            totalCards: _pendingUserVocabs.length,
          );

          _cardStartTime = DateTime.now();
          _isLoading = false;
          _isCardFlipped = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Flip current card (front <-> back)
  void flipCard() {
    _isCardFlipped = !_isCardFlipped;
    notifyListeners();
  }

  /// Submit review for current card
  Future<void> submitReview(ReviewQuality quality) async {
    if (_currentSession == null) return;

    final currentCard = _currentSession!.currentCard;
    if (currentCard == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final timeSpentMs = _cardStartTime != null
          ? DateTime.now().difference(_cardStartTime!).inMilliseconds
          : null;

      final result = await submitReviewUseCase(
        SubmitReviewParams(
          userVocabularyId: currentCard.userVocabulary.id,
          quality: quality,
          timeSpentMs: timeSpentMs,
        ),
      );

      result.fold(
        (failure) {
          _errorMessage = _getFailureMessage(failure);
          _isLoading = false;
          notifyListeners();
        },
        (reviewResult) {
          final newReviewedCount = _currentSession!.reviewedCards + 1;
          final newCorrectCount =
              _currentSession!.correctCount + (quality.isCorrect ? 1 : 0);
          final newXpEarned =
              _currentSession!.totalXpEarned + reviewResult.xpEarned;

          _currentSession = _currentSession!.copyWith(
            reviewedCards: newReviewedCount,
            correctCount: newCorrectCount,
            totalXpEarned: newXpEarned,
          );

          // Trigger background preload when approaching end of loaded cards
          final loadedCards = _currentSession!.cards.length;
          if (loadedCards - newReviewedCount <= _preloadThreshold) {
            _loadMoreCards(); // fire-and-forget
          }

          if (_currentSession!.isCompleted) {
            _currentSession = _currentSession!.copyWith(
              completedAt: DateTime.now(),
            );
          }

          _isCardFlipped = false;
          _cardStartTime = DateTime.now();
          _isLoading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _errorMessage = 'Failed to submit review: $e';
      _isLoading = false;
      notifyListeners();
    }
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

  String _getFailureMessage(failure) {
    return failure.message ?? 'An error occurred';
  }

  @override
  void dispose() {
    _currentSession = null;
    super.dispose();
  }
}
