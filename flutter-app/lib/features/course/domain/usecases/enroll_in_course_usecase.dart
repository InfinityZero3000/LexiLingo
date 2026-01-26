import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

/// Enroll the current user in a course
class EnrollInCourseUseCase implements UseCase<String, String> {
  final CourseRepository repository;

  EnrollInCourseUseCase(this.repository);

  @override
  Future<Either<Failure, String>> call(String courseId) async {
    return await repository.enrollInCourse(courseId);
  }
}
