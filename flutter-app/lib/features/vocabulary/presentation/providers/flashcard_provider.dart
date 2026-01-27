import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_due_vocabulary_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/submit_review_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// Flashcard Provider (Presentation Layer)
/// Manages flashcard review session state
/// Clean Architecture: Presentation layer orchestrates use cases
class FlashcardProvider extends ChangeNotifier {
  final GetDueVocabularyUseCase getDueVocabularyUseCase;
  final SubmitReviewUseCase submitReviewUseCase;
  final VocabularyRepository vocabularyRepository;

  FlashcardProvider({
    required this.getDueVocabularyUseCase,
    required this.submitReviewUseCase,
    required this.vocabularyRepository,
  });

  // State
  ReviewSessionEntity? _currentSession;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isCardFlipped = false;
  DateTime? _cardStartTime;

  // Getters
  ReviewSessionEntity? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isCardFlipped => _isCardFlipped;
  bool get hasSession => _currentSession != null;
  int get dueCount => _currentSession?.remainingCards ?? 0;

  /// Start a new review session
  Future<void> startReviewSession({int limit = 20}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await getDueVocabularyUseCase(
        GetDueVocabularyParams(limit: limit),
      );

      result.fold(
        (failure) {
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

          // Load full vocabulary items for each user vocabulary
          final cards = <ReviewCardEntity>[];
          
          for (final userVocab in dueVocabularyList) {
            final vocabResult = await vocabularyRepository.getVocabularyItem(
              userVocab.vocabularyId,
            );

            vocabResult.fold(
              (failure) {
                // Skip if failed to load vocabulary item
                debugPrint('Failed to load vocabulary: ${userVocab.vocabularyId}');
              },
              (vocabularyItem) {
                cards.add(ReviewCardEntity(
                  userVocabulary: userVocab,
                  vocabularyItem: vocabularyItem,
                ));
              },
            );
          }

          if (cards.isEmpty) {
            _errorMessage = 'Failed to load vocabulary items';
            _isLoading = false;
            notifyListeners();
            return;
          }

          // Create session
          _currentSession = ReviewSessionEntity(
            cards: cards,
            startedAt: DateTime.now(),
            totalCards: cards.length,
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
      // Calculate time spent on this card
      final timeSpentMs = _cardStartTime != null
          ? DateTime.now().difference(_cardStartTime!).inMilliseconds
          : null;

      // Submit review
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
          // Update session
          final newReviewedCount = _currentSession!.reviewedCards + 1;
          final newCorrectCount = _currentSession!.correctCount + 
              (quality.isCorrect ? 1 : 0);
          final newXpEarned = _currentSession!.totalXpEarned + 
              reviewResult.xpEarned;

          _currentSession = _currentSession!.copyWith(
            reviewedCards: newReviewedCount,
            correctCount: newCorrectCount,
            totalXpEarned: newXpEarned,
          );

          // Check if session is complete
          if (_currentSession!.isCompleted) {
            _currentSession = _currentSession!.copyWith(
              completedAt: DateTime.now(),
            );
          }

          // Reset card state for next card
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

  /// Get failure message
  String _getFailureMessage(failure) {
    return failure.message ?? 'An error occurred';
  }

  @override
  void dispose() {
    _currentSession = null;
    super.dispose();
  }
}
