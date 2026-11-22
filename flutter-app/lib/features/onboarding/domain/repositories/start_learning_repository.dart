import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/onboarding/domain/entities/start_learning_target.dart';

abstract class StartLearningRepository {
  Future<Either<Failure, StartLearningTarget>> startLearning({
    String? courseId,
  });
}
