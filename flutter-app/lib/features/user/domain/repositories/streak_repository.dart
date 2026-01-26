import '../entities/streak.dart';

abstract class StreakRepository {
  Future<int> getCurrentStreak(String userId);
  Future<List<Streak>> getStreakHistory(String userId, {int days = 30});
  Future<void> markDayComplete(String userId, DateTime date);
  Future<Streak?> getStreakByDate(String userId, DateTime date);
}
