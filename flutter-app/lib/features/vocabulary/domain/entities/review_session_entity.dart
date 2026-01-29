import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';

/// Review Session Entity (Domain Layer)
/// Represents a vocabulary review session
class ReviewSessionEntity {
  final List<ReviewCardEntity> cards;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int totalCards;
  final int reviewedCards;
  final int correctCount;
  final int totalXpEarned;

  const ReviewSessionEntity({
    required this.cards,
    required this.startedAt,
    this.completedAt,
    required this.totalCards,
    this.reviewedCards = 0,
    this.correctCount = 0,
    this.totalXpEarned = 0,
  });

  /// Check if session is completed
  bool get isCompleted => reviewedCards >= totalCards;

  /// Calculate session progress (0.0 - 1.0)
  double get progress {
    if (totalCards == 0) return 0.0;
    return reviewedCards / totalCards;
  }

  /// Calculate accuracy percentage
  double get accuracy {
    if (reviewedCards == 0) return 0.0;
    return (correctCount / reviewedCards) * 100;
  }

  /// Get current card
  ReviewCardEntity? get currentCard {
    if (reviewedCards < cards.length) {
      return cards[reviewedCards];
    }
    return null;
  }

  /// Get remaining cards count
  int get remainingCards => totalCards - reviewedCards;

  /// Copy with updated values
  ReviewSessionEntity copyWith({
    List<ReviewCardEntity>? cards,
    DateTime? startedAt,
    DateTime? completedAt,
    int? totalCards,
    int? reviewedCards,
    int? correctCount,
    int? totalXpEarned,
  }) {
    return ReviewSessionEntity(
      cards: cards ?? this.cards,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      totalCards: totalCards ?? this.totalCards,
      reviewedCards: reviewedCards ?? this.reviewedCards,
      correctCount: correctCount ?? this.correctCount,
      totalXpEarned: totalXpEarned ?? this.totalXpEarned,
    );
  }
}

/// Review Card Entity
/// Combines vocabulary item + user's SRS data
class ReviewCardEntity {
  final UserVocabularyEntity userVocabulary;
  final VocabularyItemEntity vocabularyItem;
  final bool isReviewed;
  final ReviewQuality? reviewQuality;

  const ReviewCardEntity({
    required this.userVocabulary,
    required this.vocabularyItem,
    this.isReviewed = false,
    this.reviewQuality,
  });

  /// Copy with updated values
  ReviewCardEntity copyWith({
    UserVocabularyEntity? userVocabulary,
    VocabularyItemEntity? vocabularyItem,
    bool? isReviewed,
    ReviewQuality? reviewQuality,
  }) {
    return ReviewCardEntity(
      userVocabulary: userVocabulary ?? this.userVocabulary,
      vocabularyItem: vocabularyItem ?? this.vocabularyItem,
      isReviewed: isReviewed ?? this.isReviewed,
      reviewQuality: reviewQuality ?? this.reviewQuality,
    );
  }
}

/// Review Quality Enum
/// Based on SuperMemo SM-2 algorithm (0-5 scale)
enum ReviewQuality {
  blackout(0, 'Complete blackout', 'Không nhớ gì'), // 0
  incorrect(1, 'Incorrect', 'Sai hoàn toàn'), // 1
  hard(2, 'Hard', 'Khó nhớ'), // 2
  good(3, 'Good', 'Tạm được'), // 3
  easy(4, 'Easy', 'Dễ'), // 4
  perfect(5, 'Perfect', 'Hoàn hảo'); // 5

  final int value;
  final String label;
  final String vietnameseLabel;

  const ReviewQuality(this.value, this.label, this.vietnameseLabel);

  /// Check if answer is correct (quality >= 3)
  bool get isCorrect => value >= 3;

  /// Get color for UI
  String get color {
    switch (this) {
      case ReviewQuality.blackout:
      case ReviewQuality.incorrect:
        return '#FF3B30'; // Red
      case ReviewQuality.hard:
        return '#FF9500'; // Orange
      case ReviewQuality.good:
        return '#FFD644'; // Yellow
      case ReviewQuality.easy:
        return '#34C759'; // Green
      case ReviewQuality.perfect:
        return '#078838'; // Dark Green
    }
  }
}

/// Review Result Entity
/// Result after submitting a review
class ReviewResultEntity {
  final String userVocabularyId;
  final ReviewQuality quality;
  final int xpEarned;
  final double newEaseFactor;
  final int newInterval;
  final int newRepetitions;
  final DateTime nextReviewDate;
  final DateTime reviewedAt;

  const ReviewResultEntity({
    required this.userVocabularyId,
    required this.quality,
    required this.xpEarned,
    required this.newEaseFactor,
    required this.newInterval,
    required this.newRepetitions,
    required this.nextReviewDate,
    required this.reviewedAt,
  });
}
