/// User Statistics Entity
class UserStatsEntity {
  final int totalXP;
  final int currentStreak;
  final int totalCoursesCompleted;
  final int totalLessonsCompleted;
  final int totalVocabularyMastered;
  final int totalTestsPassed;
  final int totalCertificatesEarned;
  final double averageTestScore;

  const UserStatsEntity({
    required this.totalXP,
    required this.currentStreak,
    required this.totalCoursesCompleted,
    required this.totalLessonsCompleted,
    required this.totalVocabularyMastered,
    required this.totalTestsPassed,
    required this.totalCertificatesEarned,
    required this.averageTestScore,
  });
}
