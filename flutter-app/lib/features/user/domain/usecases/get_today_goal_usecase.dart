import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/user/domain/entities/daily_goal.dart';
import 'package:lexilingo_app/features/user/domain/repositories/daily_goal_repository.dart';

/// Get Today's Goal Use Case
/// Retrieves the user's daily goal for today
class GetTodayGoalUseCase implements UseCase<DailyGoal?, GetTodayGoalParams> {
  final DailyGoalRepository _repository;

  GetTodayGoalUseCase({required DailyGoalRepository repository}) : _repository = repository;

  @override
  Future<Either<Failure, DailyGoal?>> call(GetTodayGoalParams params) async {
    try {
      final goal = await _repository.getTodayGoal(params.userId);
      return Right(goal);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}

/// Parameters for GetTodayGoalUseCase
class GetTodayGoalParams {
  final String userId;

  GetTodayGoalParams({required this.userId});
}
