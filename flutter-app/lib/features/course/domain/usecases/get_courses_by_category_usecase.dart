import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

/// Get Courses By Category Use Case
/// 
/// Fetches courses belonging to a specific category.
class GetCoursesByCategoryUseCase {
  final CourseRepository repository;

  GetCoursesByCategoryUseCase(this.repository);

  /// Execute the use case
  /// 
  /// Parameters:
  /// - [categoryId]: Category UUID
  /// - [page]: Page number (1-based)
  /// - [pageSize]: Items per page
  /// 
  /// Returns:
  /// - Right: (courses, totalPages) tuple
  /// - Left: Failure
  Future<Either<Failure, (List<CourseEntity>, int)>> call({
    required String categoryId,
    int page = 1,
    int pageSize = 20,
  }) async {
    return await repository.getCoursesByCategory(
      categoryId,
      page: page,
      pageSize: pageSize,
    );
  }
}
