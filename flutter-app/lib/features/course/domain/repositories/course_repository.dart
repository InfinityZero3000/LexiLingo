import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_category_entity.dart';

/// Course Repository Interface
/// Defines contract for course data operations
abstract class CourseRepository {
  /// Get paginated list of courses
  /// 
  /// Parameters:
  /// - [page]: Page number (1-based)
  /// - [pageSize]: Items per page
  /// - [language]: Optional language filter (e.g., 'en', 'vi')
  /// - [level]: Optional CEFR level filter (A1-C2)
  /// 
  /// Returns:
  /// - Right: (courses, totalPages) tuple
  /// - Left: Failure (NetworkFailure, ServerFailure, etc.)
  Future<Either<Failure, (List<CourseEntity>, int)>> getCourses({
    int page = 1,
    int pageSize = 20,
    String? language,
    String? level,
  });

  /// Get detailed course information with units and lessons
  /// 
  /// Parameters:
  /// - [courseId]: Course UUID
  /// 
  /// Returns:
  /// - Right: CourseDetailEntity with nested units/lessons
  /// - Left: Failure (NotFoundFailure, NetworkFailure, etc.)
  Future<Either<Failure, CourseDetailEntity>> getCourseDetail(String courseId);

  /// Enroll the current user in a course
  /// 
  /// Parameters:
  /// - [courseId]: Course UUID
  /// 
  /// Returns:
  /// - Right: Success message
  /// - Left: Failure (UnauthorizedFailure, AlreadyEnrolledFailure, etc.)
  Future<Either<Failure, String>> enrollInCourse(String courseId);

  /// Get all course categories
  /// 
  /// Parameters:
  /// - [activeOnly]: Only return active categories (default: true)
  /// 
  /// Returns:
  /// - Right: List of course categories
  /// - Left: Failure (NetworkFailure, ServerFailure, etc.)
  Future<Either<Failure, List<CourseCategoryEntity>>> getCategories({
    bool activeOnly = true,
  });

  /// Get courses by category
  /// 
  /// Parameters:
  /// - [categoryId]: Category UUID
  /// - [page]: Page number (1-based)
  /// - [pageSize]: Items per page
  /// 
  /// Returns:
  /// - Right: (courses, totalPages) tuple
  /// - Left: Failure (NotFoundFailure, NetworkFailure, etc.)
  Future<Either<Failure, (List<CourseEntity>, int)>> getCoursesByCategory(
    String categoryId, {
    int page = 1,
    int pageSize = 20,
  });

  /// Get enrolled courses for the current user
  /// 
  /// Parameters:
  /// - [page]: Page number (1-based)
  /// - [pageSize]: Items per page
  /// 
  /// Returns:
  /// - Right: (courses, totalPages) tuple
  /// - Left: Failure (UnauthorizedFailure, NetworkFailure, etc.)
  Future<Either<Failure, (List<CourseEntity>, int)>> getEnrolledCourses({
    int page = 1,
    int pageSize = 20,
  });
}

