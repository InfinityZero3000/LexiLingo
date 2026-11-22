import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../shared/widgets/admin_paged_list.dart';

class Course {
  final String id;
  final String title;
  final String? description;
  final String level;
  final bool isPublished;
  final String? thumbnailUrl;
  final int unitCount;
  final int lessonCount;
  final int totalXp;
  final String language;
  final List<String> tags;

  const Course({
    required this.id,
    required this.title,
    this.description,
    required this.level,
    required this.isPublished,
    this.thumbnailUrl,
    this.unitCount = 0,
    this.lessonCount = 0,
    this.totalXp = 0,
    this.language = 'en',
    this.tags = const [],
  });

  factory Course.fromJson(Map<String, dynamic> j) => Course(
    id: j['id']?.toString() ?? '',
    title: j['title'] ?? '',
    description: j['description'],
    level: j['level'] ?? 'A1',
    isPublished: j['is_published'] ?? false,
    thumbnailUrl: j['thumbnail_url'],
    unitCount: j['unit_count'] ?? 0,
    lessonCount: j['total_lessons'] ?? j['lesson_count'] ?? 0,
    totalXp: j['total_xp'] ?? 0,
    language: j['language'] ?? 'en',
    tags: (j['tags'] as List? ?? []).map((e) => e.toString()).toList(),
  );
}

class Unit {
  final String id;
  final String title;
  final int orderIndex;
  final int lessonCount;
  final String? courseId;
  final String? description;

  const Unit({
    required this.id,
    required this.title,
    required this.orderIndex,
    this.lessonCount = 0,
    this.courseId,
    this.description,
  });

  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
    id: j['id']?.toString() ?? '',
    title: j['title'] ?? '',
    orderIndex: j['order_index'] ?? 0,
    lessonCount: j['total_lessons'] ?? j['lesson_count'] ?? 0,
    courseId: j['course_id']?.toString(),
    description: j['description'],
  );
}

class Lesson {
  final String id;
  final String title;
  final String? description;
  final int orderIndex;
  final String? outcome;
  final String lessonType;

  /// CEFR skill credited on completion; null inherits the course's label.
  final String? skill;
  final int xpReward;
  final int passThreshold;
  final int totalExercises;
  final int estimatedMinutes;

  const Lesson({
    required this.id,
    required this.title,
    this.description,
    required this.orderIndex,
    this.outcome,
    this.lessonType = 'lesson',
    this.skill,
    this.xpReward = 10,
    this.passThreshold = 80,
    this.totalExercises = 0,
    this.estimatedMinutes = 10,
  });

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
    id: j['id']?.toString() ?? '',
    title: j['title'] ?? '',
    description: j['description'],
    orderIndex: j['order_index'] ?? 0,
    outcome: j['outcome'],
    lessonType: j['lesson_type'] ?? 'lesson',
    skill: j['skill'] as String?,
    xpReward: j['xp_reward'] ?? 10,
    passThreshold: j['pass_threshold'] ?? 80,
    totalExercises: j['total_exercises'] ?? 0,
    estimatedMinutes: j['estimated_minutes'] ?? 10,
  );
}

class CurriculumRepository {
  CurriculumRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<PageResult<Course>> listCourses(
    PageRequest request,
    Map<String, Object?> filters,
  ) async {
    final body = await _api.getData(
      ApiEndpoints.adminCourses,
      params: {
        ...PaginationStyle.pageSize.query(request),
        for (final e in filters.entries)
          if (e.value != null && '${e.value}'.isNotEmpty) e.key: e.value,
      },
    );
    return adminPage(body, Course.fromJson, keys: const ['courses']);
  }

  Future<PageResult<Unit>> listUnits(String courseId) async {
    final page = adminPage(
      await _api.getData(
        ApiEndpoints.adminUnits,
        params: {'course_id': courseId},
      ),
      Unit.fromJson,
      keys: const ['units'],
    );
    return PageResult(items: page.items, total: page.items.length);
  }

  Future<PageResult<Lesson>> listLessons(String unitId) async {
    final page = adminPage(
      await _api.getData(
        ApiEndpoints.adminLessons,
        params: {'unit_id': unitId},
      ),
      Lesson.fromJson,
      keys: const ['lessons'],
    );
    return PageResult(items: page.items, total: page.items.length);
  }

  Future<List<Course>> getCourses({
    int page = 1,
    String? search,
    String? level,
    bool? isPublished,
  }) async {
    final resp = await _api.get(
      ApiEndpoints.adminCourses,
      params: {
        'page': page,
        'page_size': 20,
        if (search != null) 'search': search,
        if (level != null) 'level': level,
        if (isPublished != null) 'is_published': isPublished,
      },
    );
    final data = resp['data'];
    final list = data is Map ? data['courses'] ?? [] : data ?? [];
    return (list as List).map((e) => Course.fromJson(e)).toList();
  }

  Future<void> createCourse(Map<String, dynamic> data) async {
    await _api.post(ApiEndpoints.adminCourses, data: data);
  }

  Future<void> updateCourse(String id, Map<String, dynamic> data) async {
    await _api.put('${ApiEndpoints.adminCourses}/$id', data: data);
  }

  Future<List<Unit>> getUnits(String courseId) async {
    final resp = await _api.get(
      ApiEndpoints.adminUnits,
      params: {'course_id': courseId},
    );
    final data = resp['data'];
    final list = data is List ? data : (data as Map)['units'] ?? [];
    return (list as List).map((e) => Unit.fromJson(e)).toList();
  }

  Future<void> createUnit(Map<String, dynamic> data) async {
    await _api.post(ApiEndpoints.adminUnits, data: data);
  }

  Future<void> updateUnit(String id, Map<String, dynamic> data) async {
    await _api.put('${ApiEndpoints.adminUnits}/$id', data: data);
  }

  Future<List<Lesson>> getLessons(String unitId) async {
    final resp = await _api.get(
      ApiEndpoints.adminLessons,
      params: {'unit_id': unitId},
    );
    final data = resp['data'];
    final list = data is List ? data : (data as Map)['lessons'] ?? [];
    return (list as List).map((e) => Lesson.fromJson(e)).toList();
  }

  Future<void> createLesson(Map<String, dynamic> data) async {
    await _api.post(ApiEndpoints.adminLessons, data: data);
  }

  Future<void> updateLesson(String id, Map<String, dynamic> data) async {
    await _api.put('${ApiEndpoints.adminLessons}/$id', data: data);
  }

  Future<void> publishCourse(String id) async {
    await _api.put(
      '${ApiEndpoints.adminCourses}/$id',
      data: {'is_published': true},
    );
  }

  Future<void> unpublishCourse(String id) async {
    await _api.put(
      '${ApiEndpoints.adminCourses}/$id',
      data: {'is_published': false},
    );
  }
}
