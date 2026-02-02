import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_category_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

/// Get Categories Use Case
/// 
/// Fetches all available course categories from the repository.
class GetCategoriesUseCase {
  final CourseRepository repository;

  GetCategoriesUseCase(this.repository);

  /// Execute the use case
  /// 
  /// Parameters:
  /// - [activeOnly]: Only return active categories (default: true)
  /// 
  /// Returns:
  /// - Right: List of course categories
  /// - Left: Failure
  Future<Either<Failure, List<CourseCategoryEntity>>> call({
    bool activeOnly = true,
  }) async {
    return await repository.getCategories(activeOnly: activeOnly);
  }
}
