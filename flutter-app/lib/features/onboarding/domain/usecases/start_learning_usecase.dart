import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/onboarding/domain/entities/start_learning_target.dart';
import 'package:lexilingo_app/features/onboarding/domain/repositories/start_learning_repository.dart';

class StartLearningParams {
  final String? courseId;

  const StartLearningParams({this.courseId});
}

/// Enrolls the learner and returns the first lesson to play.
class StartLearningUseCase
    implements UseCase<StartLearningTarget, StartLearningParams> {
  final StartLearningRepository repository;

  StartLearningUseCase(this.repository);

  @override
  Future<Either<Failure, StartLearningTarget>> call(
    StartLearningParams params,
  ) => repository.startLearning(courseId: params.courseId);
}
