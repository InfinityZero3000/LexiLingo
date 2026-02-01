/// Weekly Activity Entity
class WeeklyActivityEntity {
  final String date;
  final int xpEarned;
  final int lessonsCompleted;
  final int vocabularyLearned;

  const WeeklyActivityEntity({
    required this.date,
    required this.xpEarned,
    required this.lessonsCompleted,
    required this.vocabularyLearned,
  });
}
