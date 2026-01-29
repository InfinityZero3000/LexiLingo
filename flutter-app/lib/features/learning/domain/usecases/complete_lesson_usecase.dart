import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_complete_model.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

/// Complete Lesson Use Case
/// Completes the current lesson attempt and returns results
class CompleteLessonUseCase implements UseCase<LessonCompleteModel, CompleteLessonParams> {
  final LearningRepository _repository;

  CompleteLessonUseCase({required LearningRepository repository}) : _repository = repository;

  @override
  Future<Either<Failure, LessonCompleteModel>> call(CompleteLessonParams params) {
    return _repository.completeLesson(params.attemptId);
  }
}

/// Parameters for CompleteLessonUseCase
class CompleteLessonParams {
  final String attemptId;

  CompleteLessonParams({required this.attemptId});
}
