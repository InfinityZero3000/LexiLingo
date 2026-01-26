import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

/// Complete Lesson Params
class CompleteLessonParams extends Equatable {
  final String lessonId;
  final double score;

  const CompleteLessonParams({
    required this.lessonId,
    required this.score,
  });

  @override
  List<Object?> get props => [lessonId, score];
}

/// Complete Lesson UseCase
/// Marks a lesson as complete with a score
class CompleteLessonUseCase implements UseCase<LessonCompletionResult, CompleteLessonParams> {
  final ProgressRepository repository;

  CompleteLessonUseCase(this.repository);

  @override
  Future<Either<Failure, LessonCompletionResult>> call(CompleteLessonParams params) async {
    return await repository.completeLesson(
      lessonId: params.lessonId,
      score: params.score,
    );
  }
}
