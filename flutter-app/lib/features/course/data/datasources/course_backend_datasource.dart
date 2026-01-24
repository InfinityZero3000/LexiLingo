import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
import 'package:lexilingo_app/features/course/data/models/course_model.dart';
import 'package:lexilingo_app/features/course/data/models/course_detail_model.dart';

/// Course Backend Data Source
/// Handles API communication for course endpoints
abstract class CourseBackendDataSource {
  /// GET /api/v1/courses - Get paginated courses
  Future<PaginatedResponseEnvelope<List<CourseModel>>> getCourses({
    int page = 1,
    int pageSize = 20,
    String? language,
    String? level,
  });

  /// GET /api/v1/courses/{id} - Get course detail with roadmap
  Future<ApiResponseEnvelope<CourseDetailModel>> getCourseDetail(String courseId);

  /// POST /api/v1/courses/{id}/enroll - Enroll in course
  Future<ApiResponseEnvelope<Map<String, dynamic>>> enrollInCourse(String courseId);
}

/// Implementation of CourseBackendDataSource using ApiClient
class CourseBackendDataSourceImpl implements CourseBackendDataSource {
  final ApiClient apiClient;

  CourseBackendDataSourceImpl(this.apiClient);

  @override
  Future<PaginatedResponseEnvelope<List<CourseModel>>> getCourses({
    int page = 1,
    int pageSize = 20,
    String? language,
    String? level,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (language != null) queryParams['language'] = language;
    if (level != null) queryParams['level'] = level;

    final response = await apiClient.get(
      '/courses',
      queryParameters: queryParams,
    );

    return PaginatedResponseEnvelope<List<CourseModel>>.fromJson(
      response,
      (data) {
        final courses = (data as List<dynamic>)
            .map((json) => CourseModel.fromJson(json as Map<String, dynamic>))
            .toList();
        return courses;
      },
    );
  }

  @override
  Future<ApiResponseEnvelope<CourseDetailModel>> getCourseDetail(
      String courseId) async {
    final response = await apiClient.get('/courses/$courseId');

    return ApiResponseEnvelope<CourseDetailModel>.fromJson(
      response,
      (data) => CourseDetailModel.fromJson(data as Map<String, dynamic>),
    );
  }

  @override
  Future<ApiResponseEnvelope<Map<String, dynamic>>> enrollInCourse(
      String courseId) async {
    final response = await apiClient.post('/courses/$courseId/enroll');

    return ApiResponseEnvelope<Map<String, dynamic>>.fromJson(
      response,
      (data) => data as Map<String, dynamic>,
    );
  }
}
