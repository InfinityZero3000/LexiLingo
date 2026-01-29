import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/user/domain/entities/daily_goal.dart';
import 'package:lexilingo_app/features/user/domain/repositories/daily_goal_repository.dart';

/// Set Daily Goal Use Case
/// Creates or updates the user's daily goal
class SetDailyGoalUseCase implements UseCase<void, SetDailyGoalParams> {
  final DailyGoalRepository _repository;

  SetDailyGoalUseCase({required DailyGoalRepository repository}) : _repository = repository;

  @override
  Future<Either<Failure, void>> call(SetDailyGoalParams params) async {
    try {
      await _repository.createOrUpdateGoal(params.goal);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}

/// Parameters for SetDailyGoalUseCase
class SetDailyGoalParams {
  final DailyGoal goal;

  SetDailyGoalParams({required this.goal});
}
