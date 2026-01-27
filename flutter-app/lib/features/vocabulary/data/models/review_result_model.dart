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
    return ReviewResultModel(
      userVocabularyId: json['user_vocabulary_id'] as String,
      quality: _parseQuality(json['quality'] as int),
      xpEarned: (json['xp_earned'] as int?) ?? 0,
      newEaseFactor: (json['new_ease_factor'] as num).toDouble(),
      newInterval: json['new_interval'] as int,
      newRepetitions: json['new_repetitions'] as int,
      nextReviewDate: DateTime.parse(json['next_review_date'] as String),
      reviewedAt: DateTime.parse(json['reviewed_at'] as String),
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

  const ReviewSubmissionModel({
    required this.quality,
    this.timeSpentMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'quality': quality,
      if (timeSpentMs != null) 'time_spent_ms': timeSpentMs,
    };
  }
}
