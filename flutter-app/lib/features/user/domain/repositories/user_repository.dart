import '../entities/user.dart';
import '../entities/user_stats_entity.dart';
import '../entities/weekly_activity_entity.dart';
import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';

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
  
  // New methods for stats API
  Future<Either<Failure, UserStatsEntity>> getUserStats();
  Future<Either<Failure, List<WeeklyActivityEntity>>> getWeeklyActivity();
}
