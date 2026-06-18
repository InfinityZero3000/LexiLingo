import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

class GetCourseRoadmapUseCase
    implements UseCase<CourseRoadmap, GetCourseRoadmapParams> {
  final LearningRepository _repository;

  GetCourseRoadmapUseCase({required LearningRepository repository})
    : _repository = repository;

  @override
  Future<Either<Failure, CourseRoadmap>> call(GetCourseRoadmapParams params) {
    return _repository.getCourseRoadmap(params.courseId);
  }
}

/// Parameters for GetCourseRoadmapUseCase
class GetCourseRoadmapParams {
  final String courseId;

  GetCourseRoadmapParams({required this.courseId});
}
