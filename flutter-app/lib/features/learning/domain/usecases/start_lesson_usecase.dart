import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_attempt.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

class StartLessonUseCase implements UseCase<LessonAttempt, StartLessonParams> {
  final LearningRepository _repository;

  StartLessonUseCase({required LearningRepository repository})
    : _repository = repository;

  @override
  Future<Either<Failure, LessonAttempt>> call(StartLessonParams params) {
    return _repository.startLesson(params.lessonId);
  }
}

/// Parameters for StartLessonUseCase
class StartLessonParams {
  final String lessonId;

  StartLessonParams({required this.lessonId});
}
