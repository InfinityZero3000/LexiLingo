import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.id,
    required super.name,
    required super.email,
    super.avatarUrl,
    required super.joinDate,
    super.lastLoginDate,
    super.totalXP,
    super.currentStreak,
    super.longestStreak,
    super.totalLessonsCompleted,
    super.totalWordsLearned,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      joinDate: DateTime.parse(json['joinDate'] as String),
      lastLoginDate: json['lastLoginDate'] != null 
        ? DateTime.parse(json['lastLoginDate'] as String)
        : null,
      totalXP: json['totalXP'] as int? ?? 0,
      currentStreak: json['currentStreak'] as int? ?? 0,
      longestStreak: json['longestStreak'] as int? ?? 0,
      totalLessonsCompleted: json['totalLessonsCompleted'] as int? ?? 0,
      totalWordsLearned: json['totalWordsLearned'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'joinDate': joinDate.toIso8601String(),
      'lastLoginDate': lastLoginDate?.toIso8601String(),
      'totalXP': totalXP,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'totalLessonsCompleted': totalLessonsCompleted,
      'totalWordsLearned': totalWordsLearned,
    };
  }

  factory UserModel.fromEntity(User user) {
    return UserModel(
      id: user.id,
      name: user.name,
      email: user.email,
      avatarUrl: user.avatarUrl,
      joinDate: user.joinDate,
      lastLoginDate: user.lastLoginDate,
      totalXP: user.totalXP,
      currentStreak: user.currentStreak,
      longestStreak: user.longestStreak,
      totalLessonsCompleted: user.totalLessonsCompleted,
      totalWordsLearned: user.totalWordsLearned,
    );
  }
}
