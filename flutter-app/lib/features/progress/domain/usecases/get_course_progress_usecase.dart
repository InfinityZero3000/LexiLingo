import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

/// Get Course Progress UseCase
/// Retrieves detailed progress for a specific course
class GetCourseProgressUseCase implements UseCase<CourseProgressWithUnits, String> {
  final ProgressRepository repository;

  GetCourseProgressUseCase(this.repository);

  @override
  Future<Either<Failure, CourseProgressWithUnits>> call(String courseId) async {
    return await repository.getCourseProgress(courseId);
  }
}
