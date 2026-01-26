import '../entities/daily_goal.dart';
import '../repositories/daily_goal_repository.dart';

class GetGoalHistoryUseCase {
  final DailyGoalRepository repository;

  GetGoalHistoryUseCase({required this.repository});

  Future<List<DailyGoal>> call(String userId, {int days = 7}) async {
    return await repository.getGoalHistory(userId, days: days);
  }
}
