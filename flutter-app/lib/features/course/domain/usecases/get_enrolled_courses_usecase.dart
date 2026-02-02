import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

/// Get Enrolled Courses Use Case
/// 
/// Fetches courses that the current user is enrolled in.
class GetEnrolledCoursesUseCase {
  final CourseRepository repository;

  GetEnrolledCoursesUseCase(this.repository);

  /// Execute the use case
  /// 
  /// Parameters:
  /// - [page]: Page number (1-based)
  /// - [pageSize]: Items per page
  /// 
  /// Returns:
  /// - Right: (courses, totalPages) tuple
  /// - Left: Failure
  Future<Either<Failure, (List<CourseEntity>, int)>> call({
    int page = 1,
    int pageSize = 20,
  }) async {
    return await repository.getEnrolledCourses(
      page: page,
      pageSize: pageSize,
    );
  }
}
