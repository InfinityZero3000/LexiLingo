import '../entities/daily_goal.dart';

abstract class DailyGoalRepository {
  Future<DailyGoal?> getTodayGoal(String userId);
  Future<DailyGoal?> getGoalByDate(String userId, DateTime date);
  Future<List<DailyGoal>> getGoalHistory(String userId, {int days = 7});
  Future<void> createOrUpdateGoal(DailyGoal goal);
  Future<void> updateDailyProgress({
    required String userId,
    required int xpEarned,
    int lessonsCompleted = 0,
    int wordsLearned = 0,
    int minutesSpent = 0,
  });
}
