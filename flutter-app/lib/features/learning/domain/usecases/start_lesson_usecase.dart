import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_attempt_model.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

/// Start Lesson Use Case
/// Starts or resumes a lesson and returns attempt data
class StartLessonUseCase implements UseCase<LessonAttemptModel, StartLessonParams> {
  final LearningRepository _repository;

  StartLessonUseCase({required LearningRepository repository}) : _repository = repository;

  @override
  Future<Either<Failure, LessonAttemptModel>> call(StartLessonParams params) {
    return _repository.startLesson(params.lessonId);
  }
}

/// Parameters for StartLessonUseCase
class StartLessonParams {
  final String lessonId;

  StartLessonParams({required this.lessonId});
}
