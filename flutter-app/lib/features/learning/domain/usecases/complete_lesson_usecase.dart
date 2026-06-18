import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_complete.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

class CompleteLessonUseCase
    implements UseCase<LessonComplete, CompleteLessonParams> {
  final LearningRepository _repository;

  CompleteLessonUseCase({required LearningRepository repository})
    : _repository = repository;

  @override
  Future<Either<Failure, LessonComplete>> call(CompleteLessonParams params) {
    return _repository.completeLesson(params.attemptId);
  }
}

/// Parameters for CompleteLessonUseCase
class CompleteLessonParams {
  final String attemptId;

  CompleteLessonParams({required this.attemptId});
}
