import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

/// Get Course Roadmap Use Case
/// Fetches the roadmap/progress for a specific course
class GetCourseRoadmapUseCase implements UseCase<CourseRoadmapModel, GetCourseRoadmapParams> {
  final LearningRepository _repository;

  GetCourseRoadmapUseCase({required LearningRepository repository}) : _repository = repository;

  @override
  Future<Either<Failure, CourseRoadmapModel>> call(GetCourseRoadmapParams params) {
    return _repository.getCourseRoadmap(params.courseId);
  }
}

/// Parameters for GetCourseRoadmapUseCase
class GetCourseRoadmapParams {
  final String courseId;

  GetCourseRoadmapParams({required this.courseId});
}
