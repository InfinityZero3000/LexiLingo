import '../../domain/entities/daily_goal.dart';
import '../../domain/repositories/daily_goal_repository.dart';
import '../datasources/daily_goal_local_data_source.dart';
import '../models/daily_goal_model.dart';

class DailyGoalRepositoryImpl implements DailyGoalRepository {
  final DailyGoalLocalDataSource localDataSource;

  DailyGoalRepositoryImpl({required this.localDataSource});

  @override
  Future<DailyGoal?> getTodayGoal(String userId) async {
    return await localDataSource.getTodayGoal(userId);
  }

  @override
  Future<DailyGoal?> getGoalByDate(String userId, DateTime date) async {
    return await localDataSource.getGoalByDate(userId, date);
  }

  @override
  Future<List<DailyGoal>> getGoalHistory(String userId, {int days = 7}) async {
    return await localDataSource.getGoalHistory(userId, days: days);
  }

  @override
  Future<void> createOrUpdateGoal(DailyGoal goal) async {
    final goalModel = DailyGoalModel.fromEntity(goal);
    await localDataSource.createOrUpdateGoal(goalModel);
  }

  @override
  Future<void> updateDailyProgress({
    required String userId,
    required int xpEarned,
    int lessonsCompleted = 0,
    int wordsLearned = 0,
    int minutesSpent = 0,
  }) async {
    await localDataSource.updateDailyProgress(
      userId: userId,
      xpEarned: xpEarned,
      lessonsCompleted: lessonsCompleted,
      wordsLearned: wordsLearned,
      minutesSpent: minutesSpent,
    );
  }
}
