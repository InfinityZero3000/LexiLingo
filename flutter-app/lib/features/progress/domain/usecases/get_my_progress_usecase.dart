import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

/// Get My Progress UseCase
/// Retrieves user's overall progress statistics
class GetMyProgressUseCase implements UseCase<ProgressStatsEntity, NoParams> {
  final ProgressRepository repository;

  GetMyProgressUseCase(this.repository);

  @override
  Future<Either<Failure, ProgressStatsEntity>> call(NoParams params) async {
    return await repository.getMyProgress();
  }
}
