class Streak {
  final int id;
  final String userId;
  final DateTime date;
  final bool completed;

  const Streak({
    required this.id,
    required this.userId,
    required this.date,
    this.completed = false,
  });

  Streak copyWith({
    int? id,
    String? userId,
    DateTime? date,
    bool? completed,
  }) {
    return Streak(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      completed: completed ?? this.completed,
    );
  }
}
