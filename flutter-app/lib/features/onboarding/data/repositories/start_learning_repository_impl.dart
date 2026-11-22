import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failure_mapper.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/onboarding/data/datasources/start_learning_remote_datasource.dart';
import 'package:lexilingo_app/features/onboarding/domain/entities/start_learning_target.dart';
import 'package:lexilingo_app/features/onboarding/domain/repositories/start_learning_repository.dart';

class StartLearningRepositoryImpl implements StartLearningRepository {
  final StartLearningRemoteDataSource remoteDataSource;

  StartLearningRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, StartLearningTarget>> startLearning({
    String? courseId,
  }) async {
    try {
      return Right(await remoteDataSource.startLearning(courseId: courseId));
    } catch (e) {
      return Left(mapFailure(e));
    }
  }
}
