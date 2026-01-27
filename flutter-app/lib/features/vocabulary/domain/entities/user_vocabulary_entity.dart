/// User Vocabulary Entity (Domain Layer)
/// Represents user's personal vocabulary with SRS data
/// Implements SuperMemo SM-2 spaced repetition algorithm
class UserVocabularyEntity {
  final String id;
  final String userId;
  final String vocabularyId;
  final VocabularyStatus status;

  // SRS (Spaced Repetition System) fields
  final double easeFactor; // 1.3-3.0, typically starts at 2.5
  final int interval; // Days until next review
  final int repetitions; // Number of consecutive correct reviews
  final DateTime nextReviewDate;
  final DateTime? lastReviewedAt;

  // Statistics
  final int totalReviews;
  final int correctReviews;
  final int streak; // Current streak
  final int longestStreak;
  final int totalXpEarned;

  // Additional data
  final String? notes; // User's personal notes
  final DateTime addedAt;

  const UserVocabularyEntity({
    required this.id,
    required this.userId,
    required this.vocabularyId,
    required this.status,
    this.easeFactor = 2.5,
    this.interval = 1,
    this.repetitions = 0,
    required this.nextReviewDate,
    this.lastReviewedAt,
    this.totalReviews = 0,
    this.correctReviews = 0,
    this.streak = 0,
    this.longestStreak = 0,
    this.totalXpEarned = 0,
    this.notes,
    required this.addedAt,
  });

  /// Check if vocabulary is due for review
  bool get isDue {
    return DateTime.now().isAfter(nextReviewDate) || 
           DateTime.now().isAtSameMomentAs(nextReviewDate);
  }

  /// Calculate accuracy percentage
  double get accuracy {
    if (totalReviews == 0) return 0.0;
    return (correctReviews / totalReviews) * 100;
  }

  /// Check if word is mastered
  bool get isMastered {
    return status == VocabularyStatus.mastered;
  }

  /// Get status color for UI
  String get statusColor {
    switch (status) {
      case VocabularyStatus.learning:
        return '#FFD644'; // Yellow
      case VocabularyStatus.reviewing:
        return '#137FEC'; // Blue
      case VocabularyStatus.mastered:
        return '#078838'; // Green
      case VocabularyStatus.archived:
        return '#617589'; // Grey
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserVocabularyEntity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Vocabulary status enum
enum VocabularyStatus {
  learning, // Just added, < 3 reviews
  reviewing, // 3+ reviews, not mastered
  mastered, // Ease factor >= 2.5, interval >= 21 days
  archived, // User archived
}
