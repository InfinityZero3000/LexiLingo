import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
import 'package:lexilingo_app/features/course/data/models/course_model.dart';
import 'package:lexilingo_app/features/course/data/models/course_detail_model.dart';
import 'package:lexilingo_app/features/course/data/models/course_category_model.dart';

/// Course Backend Data Source
/// Handles API communication for course endpoints
abstract class CourseBackendDataSource {
  /// GET /api/v1/courses - Get paginated courses
  Future<PaginatedResponseEnvelope<CourseModel>> getCourses({
    int page = 1,
    int pageSize = 20,
    String? language,
    String? level,
  });

  /// GET /api/v1/courses/{id} - Get course detail with roadmap
  Future<ApiResponseEnvelope<CourseDetailModel>> getCourseDetail(String courseId);

  /// POST /api/v1/courses/{id}/enroll - Enroll in course
  Future<ApiResponseEnvelope<Map<String, dynamic>>> enrollInCourse(String courseId);

  /// GET /api/v1/categories - Get all categories
  Future<ApiResponseEnvelope<List<CourseCategoryModel>>> getCategories({
    bool activeOnly = true,
  });

  /// GET /api/v1/categories/{id}/courses - Get courses by category
  Future<PaginatedResponseEnvelope<CourseModel>> getCoursesByCategory(
    String categoryId, {
    int page = 1,
    int pageSize = 20,
  });

  /// GET /api/v1/courses/enrolled - Get enrolled courses
  Future<PaginatedResponseEnvelope<CourseModel>> getEnrolledCourses({
    int page = 1,
    int pageSize = 20,
  });
}

/// Implementation of CourseBackendDataSource using ApiClient
class CourseBackendDataSourceImpl implements CourseBackendDataSource {
  final ApiClient _apiClient;

  CourseBackendDataSourceImpl({required ApiClient apiClient}) : _apiClient = apiClient;

  @override
  Future<PaginatedResponseEnvelope<CourseModel>> getCourses({
    int page = 1,
    int pageSize = 20,
    String? language,
    String? level,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };
    if (language != null) queryParams['language'] = language;
    if (level != null) queryParams['level'] = level;

    final uri = Uri(
      path: '/courses',
      queryParameters: queryParams,
    );
    final response = await _apiClient.get(uri.toString());

    return PaginatedResponseEnvelope<CourseModel>.fromJson(
      response,
      (json) => CourseModel.fromJson(json),
    );
  }

  @override
  Future<ApiResponseEnvelope<CourseDetailModel>> getCourseDetail(
      String courseId) async {
    final response = await _apiClient.get('/courses/$courseId');

    return ApiResponseEnvelope<CourseDetailModel>.fromJson(
      response,
      (data) => CourseDetailModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<ApiResponseEnvelope<Map<String, dynamic>>> enrollInCourse(
      String courseId) async {
    final response = await _apiClient.post('/courses/$courseId/enroll');

    return ApiResponseEnvelope<Map<String, dynamic>>.fromJson(
      response,
      (data) => data as Map<String, dynamic>,
    );
  }

  @override
  Future<ApiResponseEnvelope<List<CourseCategoryModel>>> getCategories({
    bool activeOnly = true,
  }) async {
    final queryParams = <String, String>{
      'active_only': activeOnly.toString(),
    };

    final uri = Uri(
      path: '/categories',
      queryParameters: queryParams,
    );
    final response = await _apiClient.get(uri.toString());

    return ApiResponseEnvelope<List<CourseCategoryModel>>.fromJson(
      response,
      (data) {
        final list = data as List;
        return list.map((json) => CourseCategoryModel.fromJson(json as Map<String, dynamic>)).toList();
      },
    );
  }

  @override
  Future<PaginatedResponseEnvelope<CourseModel>> getCoursesByCategory(
    String categoryId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    final uri = Uri(
      path: '/categories/$categoryId/courses',
      queryParameters: queryParams,
    );
    final response = await _apiClient.get(uri.toString());

    return PaginatedResponseEnvelope<CourseModel>.fromJson(
      response,
      (json) => CourseModel.fromJson(json),
    );
  }

  @override
  Future<PaginatedResponseEnvelope<CourseModel>> getEnrolledCourses({
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    final uri = Uri(
      path: '/courses/enrolled',
      queryParameters: queryParams,
    );
    final response = await _apiClient.get(uri.toString());

    return PaginatedResponseEnvelope<CourseModel>.fromJson(
      response,
      (json) => CourseModel.fromJson(json),
    );
  }
}
