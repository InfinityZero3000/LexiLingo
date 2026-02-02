/// Vocabulary status enumeration
enum VocabularyStatus {
  learning,
  reviewing,
  mastered,
  archived,
}

/// User Vocabulary Entity (Domain Layer)
class UserVocabularyEntity {
  final String id;
  final String userId;
  final String vocabularyId;
  final VocabularyStatus status;
  final double? easeFactor;
  final int? interval;
  final int? repetitions;
  final DateTime nextReviewDate;
  final DateTime? lastReviewedAt;
  final int? totalReviews;
  final int? correctReviews;
  final int? streak;
  final int? longestStreak;
  final int? totalXpEarned;
  final String? notes;
  final DateTime addedAt;

  const UserVocabularyEntity({
    required this.id,
    required this.userId,
    required this.vocabularyId,
    required this.status,
    this.easeFactor,
    this.interval,
    this.repetitions,
    required this.nextReviewDate,
    this.lastReviewedAt,
    this.totalReviews,
    this.correctReviews,
    this.streak,
    this.longestStreak,
    this.totalXpEarned,
    this.notes,
    required this.addedAt,
  });
}
