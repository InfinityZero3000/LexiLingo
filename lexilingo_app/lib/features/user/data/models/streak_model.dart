import '../../domain/entities/streak.dart';

class StreakModel extends Streak {
  const StreakModel({
    required super.id,
    required super.userId,
    required super.date,
    super.completed,
  });

  factory StreakModel.fromJson(Map<String, dynamic> json) {
    return StreakModel(
      id: json['id'] as int,
      userId: json['userId'] as String,
      date: DateTime.parse(json['date'] as String),
      completed: (json['completed'] as int?) == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'completed': completed ? 1 : 0,
    };
  }

  factory StreakModel.fromEntity(Streak streak) {
    return StreakModel(
      id: streak.id,
      userId: streak.userId,
      date: streak.date,
      completed: streak.completed,
    );
  }
}
