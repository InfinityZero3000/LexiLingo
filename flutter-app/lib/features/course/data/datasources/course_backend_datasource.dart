import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
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
  Future<ApiResponseEnvelope<CourseDetailModel>> getCourseDetail(
    String courseId,
  );

  /// POST /api/v1/courses/{id}/enroll - Enroll in course
  Future<ApiResponseEnvelope<Map<String, dynamic>>> enrollInCourse(
    String courseId,
  );

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
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  CourseBackendDataSourceImpl({required ApiClient apiClient})
    : _apiClient = apiClient;

  RequestMeta _localMeta() {
    return RequestMeta(
      requestId: 'local-sqlite-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now().toIso8601String(),
    );
  }

  Future<PaginatedResponseEnvelope<CourseModel>> _localCoursesPage({
    required int page,
    required int pageSize,
    String? category,
    bool enrolledOnly = false,
  }) async {
    final db = await _dbHelper.database;

    final safePage = page < 1 ? 1 : page;
    final safePageSize = pageSize < 1 ? 20 : pageSize;
    final offset = (safePage - 1) * safePageSize;

    String whereClause = '';
    final whereArgs = <Object?>[];
    if (category != null && category.isNotEmpty) {
      whereClause = 'WHERE c.category = ?';
      whereArgs.add(category);
    }
    if (enrolledOnly) {
      whereClause = whereClause.isEmpty
          ? 'WHERE e.userId = ?'
          : '$whereClause AND e.userId = ?';
      whereArgs.add('demo_user_001');
    }

    final countResult = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT c.id) as total
      FROM courses c
      LEFT JOIN course_enrollments e ON c.id = e.courseId
      $whereClause
      ''',
      whereArgs,
    );

    final total = (countResult.first['total'] as int?) ?? 0;
    final totalPages = total == 0 ? 0 : ((total + safePageSize - 1) ~/ safePageSize);

    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT
        c.id,
        c.title,
        c.description,
        c.level,
        c.category,
        c.imageUrl,
        c.lessonsCount,
        c.duration,
        c.isFeatured,
        c.rating,
        c.enrolledCount,
        c.createdAt,
        c.updatedAt,
        CASE WHEN e.userId IS NOT NULL THEN 1 ELSE 0 END AS isEnrolled,
        COALESCE(e.currentProgress, c.progress, 0.0) AS userProgress
      FROM courses c
      LEFT JOIN course_enrollments e ON c.id = e.courseId AND e.userId = 'demo_user_001'
      $whereClause
      ORDER BY c.isFeatured DESC, c.rating DESC, c.id ASC
      LIMIT ? OFFSET ?
      ''',
      [...whereArgs, safePageSize, offset],
    );

    final data = rows.map((row) {
      final lessonsCount = (row['lessonsCount'] as int?) ?? 0;
      return CourseModel(
        id: (row['id'] ?? '').toString(),
        title: (row['title'] ?? '').toString(),
        description: row['description']?.toString(),
        language: 'en',
        level: (row['level'] ?? 'A1').toString(),
        tags: row['category'] == null ? [] : [row['category'].toString().toLowerCase()],
        thumbnailUrl: row['imageUrl']?.toString(),
        totalXp: lessonsCount * 50,
        estimatedDuration: lessonsCount * 10,
        totalLessons: lessonsCount,
        isPublished: true,
        createdAt: DateTime.tryParse(row['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(row['updatedAt']?.toString() ?? '') ?? DateTime.now(),
        isEnrolled: (row['isEnrolled'] as int? ?? 0) == 1,
        userProgress: (row['userProgress'] as num?)?.toDouble(),
      );
    }).toList();

    return PaginatedResponseEnvelope<CourseModel>(
      data: data,
      pagination: PaginationMeta(
        page: safePage,
        pageSize: safePageSize,
        total: total,
        totalPages: totalPages,
      ),
      meta: _localMeta(),
    );
  }

  Future<ApiResponseEnvelope<CourseDetailModel>?> _localCourseDetail(
    String courseId,
  ) async {
    final localCourseId = int.tryParse(courseId);
    if (localCourseId == null) {
      return null;
    }

    final db = await _dbHelper.database;
    final rows = await db.query(
      'courses',
      where: 'id = ?',
      whereArgs: [localCourseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final course = rows.first;
    final lessons = await db.query(
      'lessons',
      where: 'courseId = ?',
      whereArgs: [localCourseId],
      orderBy: 'orderIndex ASC',
    );

    final lessonModels = lessons.map((row) {
      final status = (row['status'] ?? '').toString().toLowerCase();
      return LessonInRoadmapModel(
        id: (row['id'] ?? '').toString(),
        title: (row['title'] ?? '').toString(),
        orderIndex: (row['orderIndex'] as int?) ?? 1,
        lessonType: 'practice',
        xpReward: 10,
        isLocked: status == 'locked',
        isCompleted: status == 'completed',
      );
    }).toList();

    final detail = CourseDetailModel(
      id: (course['id'] ?? '').toString(),
      title: (course['title'] ?? '').toString(),
      description: course['description']?.toString(),
      language: 'en',
      level: (course['level'] ?? 'A1').toString(),
      tags: course['category'] == null ? [] : [course['category'].toString().toLowerCase()],
      thumbnailUrl: course['imageUrl']?.toString(),
      totalXp: ((course['lessonsCount'] as int?) ?? 0) * 50,
      estimatedDuration: ((course['lessonsCount'] as int?) ?? 0) * 10,
      totalLessons: (course['lessonsCount'] as int?) ?? 0,
      isPublished: true,
      createdAt: DateTime.tryParse(course['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(course['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      isEnrolled: (course['isEnrolled'] as int? ?? 0) == 1,
      userProgress: (course['progress'] as num?)?.toDouble(),
      units: [
        UnitWithLessonsModel(
          id: 'unit-$courseId',
          title: 'Roadmap',
          description: 'Complete lessons in order for best progress.',
          orderIndex: 1,
          backgroundColor: '#1F2937',
          iconUrl: null,
          lessons: lessonModels,
        ),
      ],
    );

    return ApiResponseEnvelope<CourseDetailModel>(
      data: detail,
      meta: _localMeta(),
    );
  }

  Future<ApiResponseEnvelope<List<CourseCategoryModel>>> _localCategories() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT category, COUNT(*) as course_count
      FROM courses
      WHERE category IS NOT NULL AND category != ''
      GROUP BY category
      ORDER BY course_count DESC, category ASC
    ''');

    final categories = rows.map((row) {
      final name = (row['category'] ?? 'General').toString();
      final slug = name.toLowerCase().replaceAll(' ', '-');
      return CourseCategoryModel(
        id: slug,
        name: name,
        slug: slug,
        description: '$name learning track',
        icon: null,
        color: null,
        courseCount: (row['course_count'] as int?) ?? 0,
      );
    }).toList();

    return ApiResponseEnvelope<List<CourseCategoryModel>>(
      data: categories,
      meta: _localMeta(),
    );
  }

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

    try {
      final uri = Uri(path: '/courses', queryParameters: queryParams);
      final response = await _apiClient.get(uri.toString());

      final parsed = PaginatedResponseEnvelope<CourseModel>.fromJson(
        response,
        (json) => CourseModel.fromJson(json),
      );
      if (parsed.data.isNotEmpty) {
        return parsed;
      }
    } catch (_) {
      // Fall through to local SQLite fallback.
    }

    return _localCoursesPage(page: page, pageSize: pageSize);
  }

  @override
  Future<ApiResponseEnvelope<CourseDetailModel>> getCourseDetail(
    String courseId,
  ) async {
    try {
      final response = await _apiClient.get('/courses/$courseId');
      return ApiResponseEnvelope<CourseDetailModel>.fromJson(
        response,
        (data) => CourseDetailModel.fromJson(data as Map<String, dynamic>),
      );
    } catch (_) {
      final local = await _localCourseDetail(courseId);
      if (local != null) {
        return local;
      }
      rethrow;
    }
  }

  @override
  Future<ApiResponseEnvelope<Map<String, dynamic>>> enrollInCourse(
    String courseId,
  ) async {
    try {
      final response = await _apiClient.post('/courses/$courseId/enroll');
      return ApiResponseEnvelope<Map<String, dynamic>>.fromJson(
        response,
        (data) => data as Map<String, dynamic>,
      );
    } catch (_) {
      final localCourseId = int.tryParse(courseId);
      if (localCourseId == null) rethrow;

      final db = await _dbHelper.database;
      await db.insert('course_enrollments', {
        'userId': 'demo_user_001',
        'courseId': localCourseId,
        'enrolledAt': DateTime.now().toIso8601String(),
        'lastAccessedAt': DateTime.now().toIso8601String(),
        'currentProgress': 0.0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.update(
        'courses',
        {'isEnrolled': 1, 'progress': 0.0},
        where: 'id = ?',
        whereArgs: [localCourseId],
      );

      return ApiResponseEnvelope<Map<String, dynamic>>(
        data: const {'message': 'Enrolled successfully (local mode)'},
        meta: _localMeta(),
      );
    }
  }

  @override
  Future<ApiResponseEnvelope<List<CourseCategoryModel>>> getCategories({
    bool activeOnly = true,
  }) async {
    try {
      final queryParams = <String, String>{'active_only': activeOnly.toString()};
      final uri = Uri(path: '/categories', queryParameters: queryParams);
      final response = await _apiClient.get(uri.toString());
      final parsed = ApiResponseEnvelope<List<CourseCategoryModel>>.fromJson(
        response,
        (data) {
          final list = data as List;
          return list
              .map(
                (json) =>
                    CourseCategoryModel.fromJson(json as Map<String, dynamic>),
              )
              .toList();
        },
      );
      if (parsed.data.isNotEmpty) {
        return parsed;
      }
    } catch (_) {
      // Fall through to local SQLite fallback.
    }

    return _localCategories();
  }

  @override
  Future<PaginatedResponseEnvelope<CourseModel>> getCoursesByCategory(
    String categoryId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };
      final uri = Uri(
        path: '/categories/$categoryId/courses',
        queryParameters: queryParams,
      );
      final response = await _apiClient.get(uri.toString());
      final parsed = PaginatedResponseEnvelope<CourseModel>.fromJson(
        response,
        (json) => CourseModel.fromJson(json),
      );
      if (parsed.data.isNotEmpty) {
        return parsed;
      }
    } catch (_) {
      // Fall through to local SQLite fallback.
    }

    final normalized = categoryId.toLowerCase().replaceAll('-', ' ');
    final titleCase = normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
    return _localCoursesPage(
      page: page,
      pageSize: pageSize,
      category: titleCase,
    );
  }

  @override
  Future<PaginatedResponseEnvelope<CourseModel>> getEnrolledCourses({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };

      final uri = Uri(path: '/courses/enrolled', queryParameters: queryParams);
      final response = await _apiClient.get(uri.toString());
      final parsed = PaginatedResponseEnvelope<CourseModel>.fromJson(
        response,
        (json) => CourseModel.fromJson(json),
      );
      if (parsed.data.isNotEmpty) {
        return parsed;
      }
    } catch (_) {
      // Fall through to local SQLite fallback.
    }

    return _localCoursesPage(
      page: page,
      pageSize: pageSize,
      enrolledOnly: true,
    );
  }
}
