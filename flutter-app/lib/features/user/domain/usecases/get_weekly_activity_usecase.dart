import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/user/domain/entities/weekly_activity_entity.dart';
import 'package:lexilingo_app/features/user/domain/repositories/user_repository.dart';

/// Use case for getting weekly activity data
class GetWeeklyActivityUseCase {
  final UserRepository repository;

  const GetWeeklyActivityUseCase(this.repository);

  Future<Either<Failure, List<WeeklyActivityEntity>>> call() {
    return repository.getWeeklyActivity();
  }
}
