import 'package:lexilingo_app/features/user/domain/entities/user_stats_entity.dart';

/// User Statistics Model
class UserStatsModel extends UserStatsEntity {
  const UserStatsModel({
    required super.totalXP,
    required super.currentStreak,
    required super.totalCoursesCompleted,
    required super.totalLessonsCompleted,
    required super.totalVocabularyMastered,
    required super.totalTestsPassed,
    required super.totalCertificatesEarned,
    required super.averageTestScore,
  });

  factory UserStatsModel.fromJson(Map<String, dynamic> json) {
    return UserStatsModel(
      totalXP: json['total_xp'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      totalCoursesCompleted: json['total_courses_completed'] as int? ?? 0,
      totalLessonsCompleted: json['total_lessons_completed'] as int? ?? 0,
      totalVocabularyMastered: json['total_vocabulary_mastered'] as int? ?? 0,
      totalTestsPassed: json['total_tests_passed'] as int? ?? 0,
      totalCertificatesEarned: json['total_certificates_earned'] as int? ?? 0,
      averageTestScore: (json['average_test_score'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_xp': totalXP,
      'current_streak': currentStreak,
      'total_courses_completed': totalCoursesCompleted,
      'total_lessons_completed': totalLessonsCompleted,
      'total_vocabulary_mastered': totalVocabularyMastered,
      'total_tests_passed': totalTestsPassed,
      'total_certificates_earned': totalCertificatesEarned,
      'average_test_score': averageTestScore,
    };
  }
}
