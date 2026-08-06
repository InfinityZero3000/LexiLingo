import '../../../core/network/api_client.dart';
import '../../../core/constants/api_endpoints.dart';

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
        xpReward: j['xp_reward'] ?? 10,
        passThreshold: j['pass_threshold'] ?? 80,
        totalExercises: j['total_exercises'] ?? 0,
        estimatedMinutes: j['estimated_minutes'] ?? 10,
      );
}

class CurriculumRepository {
  final _api = ApiClient.instance;

  Future<List<Course>> getCourses({int page = 1, String? search, String? level, bool? isPublished}) async {
    final resp = await _api.get(ApiEndpoints.adminCourses, params: {
      'page': page,
      'page_size': 20,
      if (search != null) 'search': search,
      if (level != null) 'level': level,
      if (isPublished != null) 'is_published': isPublished,
    });
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
    final resp = await _api.get(ApiEndpoints.adminUnits, params: {'course_id': courseId});
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

  Future<void> deleteUnit(String id) async {
    await _api.delete('${ApiEndpoints.adminUnits}/$id');
  }

  Future<List<Lesson>> getLessons(String unitId) async {
    final resp = await _api.get(ApiEndpoints.adminLessons, params: {'unit_id': unitId});
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

  Future<void> deleteLesson(String id) async {
    await _api.delete('${ApiEndpoints.adminLessons}/$id');
  }

  Future<void> publishCourse(String id) async {
    await _api.put('${ApiEndpoints.adminCourses}/$id', data: {'is_published': true});
  }

  Future<void> unpublishCourse(String id) async {
    await _api.put('${ApiEndpoints.adminCourses}/$id', data: {'is_published': false});
  }

  Future<void> deleteCourse(String id) async {
    await _api.delete('${ApiEndpoints.adminCourses}/$id');
  }
}
