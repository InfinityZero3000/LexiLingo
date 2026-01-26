class User {
  final String id; // Firebase UID
  final String name;
  final String email;
  final String? avatarUrl;
  final DateTime joinDate;
  final DateTime? lastLoginDate;
  final int totalXP;
  final int currentStreak;
  final int longestStreak;
  final int totalLessonsCompleted;
  final int totalWordsLearned;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.joinDate,
    this.lastLoginDate,
    this.totalXP = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalLessonsCompleted = 0,
    this.totalWordsLearned = 0,
  });

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    DateTime? joinDate,
    DateTime? lastLoginDate,
    int? totalXP,
    int? currentStreak,
    int? longestStreak,
    int? totalLessonsCompleted,
    int? totalWordsLearned,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      joinDate: joinDate ?? this.joinDate,
      lastLoginDate: lastLoginDate ?? this.lastLoginDate,
      totalXP: totalXP ?? this.totalXP,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      totalLessonsCompleted: totalLessonsCompleted ?? this.totalLessonsCompleted,
      totalWordsLearned: totalWordsLearned ?? this.totalWordsLearned,
    );
  }
}
