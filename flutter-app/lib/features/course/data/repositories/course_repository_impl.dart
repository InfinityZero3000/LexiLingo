import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/features/course/data/datasources/course_backend_datasource.dart';
import 'package:lexilingo_app/features/course/data/datasources/course_local_datasource.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_category_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

/// Course Repository Implementation
/// Implements business logic, error handling, and caching
/// 
/// Following agent-skills/language-learning-patterns:
/// - Cache categories locally for faster load times
/// - Reduce API calls for rarely-changing data
class CourseRepositoryImpl implements CourseRepository {
  final CourseBackendDataSource backendDataSource;
  final CourseLocalDataSource? localDataSource;

  CourseRepositoryImpl({
    required this.backendDataSource,
    this.localDataSource,
  });

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> getCourses({
    int page = 1,
    int pageSize = 20,
    String? language,
    String? level,
  }) async {
    try {
      final response = await backendDataSource.getCourses(
        page: page,
        pageSize: pageSize,
        language: language,
        level: level,
      );

      final courses = response.data.map((model) => model as CourseEntity).toList();
      final totalPages = response.pagination.totalPages;

      return Right((courses, totalPages));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, CourseDetailEntity>> getCourseDetail(String courseId) async {
    try {
      final response = await backendDataSource.getCourseDetail(courseId);
      return Right(response.data);
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, String>> enrollInCourse(String courseId) async {
    try {
      final response = await backendDataSource.enrollInCourse(courseId);
      final message = response.data['message'] as String? ?? 'Successfully enrolled';
      return Right(message);
    } on BadRequestException catch (e) {
      return Left(ServerFailure(e.message));
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, List<CourseCategoryEntity>>> getCategories({
    bool activeOnly = true,
  }) async {
    try {
      // Try to get from cache first (if local datasource available)
      if (localDataSource != null) {
        final isCacheValid = await localDataSource!.isCategoryCacheValid();
        if (isCacheValid) {
          final cachedCategories = await localDataSource!.getCachedCategories();
          if (cachedCategories != null && cachedCategories.isNotEmpty) {
            return Right(cachedCategories.map((m) => m as CourseCategoryEntity).toList());
          }
        }
      }
      
      // Fetch from backend
      final response = await backendDataSource.getCategories(activeOnly: activeOnly);
      final categories = response.data.map((model) => model as CourseCategoryEntity).toList();
      
      // Cache the result (response.data already returns CourseCategoryModel)
      if (localDataSource != null && categories.isNotEmpty) {
        await localDataSource!.cacheCategories(response.data);
      }
      
      return Right(categories);
    } on ServerException catch (e) {
      // On server error, try to return cached data as fallback
      if (localDataSource != null) {
        final cachedCategories = await localDataSource!.getCachedCategories();
        if (cachedCategories != null && cachedCategories.isNotEmpty) {
          return Right(cachedCategories.map((m) => m as CourseCategoryEntity).toList());
        }
      }
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      // On network error, try to return cached data as fallback
      if (localDataSource != null) {
        final cachedCategories = await localDataSource!.getCachedCategories();
        if (cachedCategories != null && cachedCategories.isNotEmpty) {
          return Right(cachedCategories.map((m) => m as CourseCategoryEntity).toList());
        }
      }
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> getCoursesByCategory(
    String categoryId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await backendDataSource.getCoursesByCategory(
        categoryId,
        page: page,
        pageSize: pageSize,
      );

      final courses = response.data.map((model) => model as CourseEntity).toList();
      final totalPages = response.pagination.totalPages;

      return Right((courses, totalPages));
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> getEnrolledCourses({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await backendDataSource.getEnrolledCourses(
        page: page,
        pageSize: pageSize,
      );

      final courses = response.data.map((model) => model as CourseEntity).toList();
      final totalPages = response.pagination.totalPages;

      return Right((courses, totalPages));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: ${e.toString()}'));
    }
  }
}


