import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';

/// Review Result Model (Data Layer)
/// Converts between API JSON and Domain Entity
class ReviewResultModel extends ReviewResultEntity {
  const ReviewResultModel({
    required super.userVocabularyId,
    required super.quality,
    required super.xpEarned,
    required super.newEaseFactor,
    required super.newInterval,
    required super.newRepetitions,
    required super.nextReviewDate,
    required super.reviewedAt,
  });

  /// Create from JSON (API response)
  factory ReviewResultModel.fromJson(Map<String, dynamic> json) {
    final userVocabulary = json['user_vocabulary'] is Map<String, dynamic>
        ? json['user_vocabulary'] as Map<String, dynamic>
        : <String, dynamic>{};
    final qualityValue = json['quality'] as int? ?? 3;
    final nextReviewRaw =
        (json['next_review_date'] as String?) ??
        (userVocabulary['next_review_date'] as String?);
    final reviewedAtRaw =
        (json['reviewed_at'] as String?) ??
        (userVocabulary['last_reviewed_at'] as String?);

    return ReviewResultModel(
      userVocabularyId:
          (json['user_vocabulary_id'] as String?) ??
          (userVocabulary['id'] as String?) ??
          '',
      quality: _parseQuality(qualityValue),
      xpEarned:
          (json['xp_earned'] as int?) ?? (json['xp_awarded'] as int?) ?? 0,
      newEaseFactor:
          (json['new_ease_factor'] as num?)?.toDouble() ??
          (userVocabulary['ease_factor'] as num?)?.toDouble() ??
          2.5,
      newInterval:
          (json['new_interval'] as int?) ??
          (userVocabulary['interval'] as int?) ??
          (json['next_review_in_days'] as int?) ??
          1,
      newRepetitions:
          (json['new_repetitions'] as int?) ??
          (userVocabulary['repetitions'] as int?) ??
          0,
      nextReviewDate: nextReviewRaw != null
          ? DateTime.parse(nextReviewRaw)
          : DateTime.now(),
      reviewedAt: reviewedAtRaw != null
          ? DateTime.parse(reviewedAtRaw)
          : DateTime.now(),
    );
  }

  /// Convert to JSON (API request)
  Map<String, dynamic> toJson() {
    return {
      'user_vocabulary_id': userVocabularyId,
      'quality': quality.value,
      'xp_earned': xpEarned,
      'new_ease_factor': newEaseFactor,
      'new_interval': newInterval,
      'new_repetitions': newRepetitions,
      'next_review_date': nextReviewDate.toIso8601String(),
      'reviewed_at': reviewedAt.toIso8601String(),
    };
  }

  /// Parse review quality from integer
  static ReviewQuality _parseQuality(int value) {
    switch (value) {
      case 0:
        return ReviewQuality.blackout;
      case 1:
        return ReviewQuality.incorrect;
      case 2:
        return ReviewQuality.hard;
      case 3:
        return ReviewQuality.good;
      case 4:
        return ReviewQuality.easy;
      case 5:
        return ReviewQuality.perfect;
      default:
        return ReviewQuality.good;
    }
  }

  /// Convert to Entity
  ReviewResultEntity toEntity() {
    return ReviewResultEntity(
      userVocabularyId: userVocabularyId,
      quality: quality,
      xpEarned: xpEarned,
      newEaseFactor: newEaseFactor,
      newInterval: newInterval,
      newRepetitions: newRepetitions,
      nextReviewDate: nextReviewDate,
      reviewedAt: reviewedAt,
    );
  }
}

/// Review Submission Request Model
class ReviewSubmissionModel {
  final int quality; // 0-5
  final int? timeSpentMs; // Optional: time spent on card

  const ReviewSubmissionModel({required this.quality, this.timeSpentMs});

  Map<String, dynamic> toJson() {
    return {
      'quality': quality,
      if (timeSpentMs != null) 'time_spent_ms': timeSpentMs,
    };
  }
}
