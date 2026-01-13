import '../entities/daily_goal.dart';
import '../repositories/daily_goal_repository.dart';

class GetTodayGoalUseCase {
  final DailyGoalRepository repository;

  GetTodayGoalUseCase({required this.repository});

  Future<DailyGoal?> call(String userId) async {
    return await repository.getTodayGoal(userId);
  }
}
