class DailyGoal {
  final int id;
  final String userId;
  final DateTime date;
  final int targetXP;
  final int earnedXP;
  final int lessonsCompleted;
  final int wordsLearned;
  final int minutesSpent;

  const DailyGoal({
    required this.id,
    required this.userId,
    required this.date,
    this.targetXP = 50,
    this.earnedXP = 0,
    this.lessonsCompleted = 0,
    this.wordsLearned = 0,
    this.minutesSpent = 0,
  });

  double get progressPercentage {
    if (targetXP == 0) return 0.0;
    return (earnedXP / targetXP).clamp(0.0, 1.0);
  }

  bool get isCompleted => earnedXP >= targetXP;

  DailyGoal copyWith({
    int? id,
    String? userId,
    DateTime? date,
    int? targetXP,
    int? earnedXP,
    int? lessonsCompleted,
    int? wordsLearned,
    int? minutesSpent,
  }) {
    return DailyGoal(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      targetXP: targetXP ?? this.targetXP,
      earnedXP: earnedXP ?? this.earnedXP,
      lessonsCompleted: lessonsCompleted ?? this.lessonsCompleted,
      wordsLearned: wordsLearned ?? this.wordsLearned,
      minutesSpent: minutesSpent ?? this.minutesSpent,
    );
  }
}
