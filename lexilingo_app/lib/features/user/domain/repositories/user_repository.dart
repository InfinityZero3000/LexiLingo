import '../entities/user.dart';

abstract class UserRepository {
  Future<User?> getUser(String userId);
  Future<void> createUser(User user);
  Future<void> updateUser(User user);
  Future<void> updateUserStats({
    required String userId,
    int? totalXP,
    int? currentStreak,
    int? longestStreak,
    int? totalLessonsCompleted,
    int? totalWordsLearned,
  });
  Future<void> updateLastLogin(String userId);
}
