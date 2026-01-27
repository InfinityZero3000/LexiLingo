import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';

/// User Vocabulary Model (Data Layer)
/// Converts between API JSON and Domain Entity
class UserVocabularyModel extends UserVocabularyEntity {
  const UserVocabularyModel({
    required super.id,
    required super.userId,
    required super.vocabularyId,
    required super.status,
    super.easeFactor,
    super.interval,
    super.repetitions,
    required super.nextReviewDate,
    super.lastReviewedAt,
    super.totalReviews,
    super.correctReviews,
    super.streak,
    super.longestStreak,
    super.totalXpEarned,
    super.notes,
    required super.addedAt,
  });

  /// Create from JSON (API response)
  factory UserVocabularyModel.fromJson(Map<String, dynamic> json) {
    return UserVocabularyModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      vocabularyId: json['vocabulary_id'] as String,
      status: _parseStatus(json['status'] as String),
      easeFactor: (json['ease_factor'] as num?)?.toDouble() ?? 2.5,
      interval: (json['interval'] as int?) ?? 1,
      repetitions: (json['repetitions'] as int?) ?? 0,
      nextReviewDate: DateTime.parse(json['next_review_date'] as String),
      lastReviewedAt: json['last_reviewed_at'] != null
          ? DateTime.parse(json['last_reviewed_at'] as String)
          : null,
      totalReviews: (json['total_reviews'] as int?) ?? 0,
      correctReviews: (json['correct_reviews'] as int?) ?? 0,
      streak: (json['streak'] as int?) ?? 0,
      longestStreak: (json['longest_streak'] as int?) ?? 0,
      totalXpEarned: (json['total_xp_earned'] as int?) ?? 0,
      notes: json['notes'] as String?,
      addedAt: DateTime.parse(json['added_at'] as String),
    );
  }

  /// Convert to JSON (API request)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'vocabulary_id': vocabularyId,
      'status': _statusToString(status),
      'ease_factor': easeFactor,
      'interval': interval,
      'repetitions': repetitions,
      'next_review_date': nextReviewDate.toIso8601String(),
      'last_reviewed_at': lastReviewedAt?.toIso8601String(),
      'total_reviews': totalReviews,
      'correct_reviews': correctReviews,
      'streak': streak,
      'longest_streak': longestStreak,
      'total_xp_earned': totalXpEarned,
      'notes': notes,
      'added_at': addedAt.toIso8601String(),
    };
  }

  /// Convert to Entity
  UserVocabularyEntity toEntity() {
    return UserVocabularyEntity(
      id: id,
      userId: userId,
      vocabularyId: vocabularyId,
      status: status,
      easeFactor: easeFactor,
      interval: interval,
      repetitions: repetitions,
      nextReviewDate: nextReviewDate,
      lastReviewedAt: lastReviewedAt,
      totalReviews: totalReviews,
      correctReviews: correctReviews,
      streak: streak,
      longestStreak: longestStreak,
      totalXpEarned: totalXpEarned,
      notes: notes,
      addedAt: addedAt,
    );
  }

  /// Parse status from string
  static VocabularyStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'learning':
        return VocabularyStatus.learning;
      case 'reviewing':
        return VocabularyStatus.reviewing;
      case 'mastered':
        return VocabularyStatus.mastered;
      case 'archived':
        return VocabularyStatus.archived;
      default:
        return VocabularyStatus.learning;
    }
  }

  /// Convert status to string
  static String _statusToString(VocabularyStatus status) {
    return status.toString().split('.').last;
  }
}
