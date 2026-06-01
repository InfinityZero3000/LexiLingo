import '../../../core/network/api_client.dart';

class Course {
  final String id;
  final String title;
  final String? description;
  final String level;
  final bool isPublished;
  final String? thumbnailUrl;
  final int unitCount;
  final int lessonCount;

  const Course({
    required this.id,
    required this.title,
    this.description,
    required this.level,
    required this.isPublished,
    this.thumbnailUrl,
    this.unitCount = 0,
    this.lessonCount = 0,
  });

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id']?.toString() ?? '',
        title: j['title'] ?? '',
        description: j['description'],
        level: j['level'] ?? 'A1',
        isPublished: j['is_published'] ?? false,
        thumbnailUrl: j['thumbnail_url'],
        unitCount: j['unit_count'] ?? 0,
        lessonCount: j['lesson_count'] ?? 0,
      );
}

class Unit {
  final String id;
  final String title;
  final int orderIndex;
  final int lessonCount;
  final String? courseId;

  const Unit({
    required this.id,
    required this.title,
    required this.orderIndex,
    this.lessonCount = 0,
    this.courseId,
  });

  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
        id: j['id']?.toString() ?? '',
        title: j['title'] ?? '',
        orderIndex: j['order_index'] ?? 0,
        lessonCount: j['lesson_count'] ?? 0,
        courseId: j['course_id']?.toString(),
      );
}

class Lesson {
  final String id;
  final String title;
  final String? description;
  final String status;
  final int orderIndex;

  const Lesson({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    required this.orderIndex,
  });

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        id: j['id']?.toString() ?? '',
        title: j['title'] ?? '',
        description: j['description'],
        status: j['status'] ?? 'draft',
        orderIndex: j['order_index'] ?? 0,
      );
}

class CurriculumRepository {
  final _api = ApiClient.instance;

  Future<List<Course>> getCourses({int page = 1, String? search}) async {
    final resp = await _api.get('/admin/courses', params: {
      'page': page,
      'page_size': 20,
      if (search != null) 'search': search,
    });
    final data = resp['data'];
    final list = data is Map ? data['courses'] ?? [] : data ?? [];
    return (list as List).map((e) => Course.fromJson(e)).toList();
  }

  Future<List<Unit>> getUnits(String courseId) async {
    final resp = await _api.get('/admin/units', params: {'course_id': courseId});
    final data = resp['data'];
    final list = data is List ? data : (data as Map)['units'] ?? [];
    return (list as List).map((e) => Unit.fromJson(e)).toList();
  }

  Future<List<Lesson>> getLessons(String unitId) async {
    final resp = await _api.get('/admin/lessons', params: {'unit_id': unitId});
    final data = resp['data'];
    final list = data is List ? data : (data as Map)['lessons'] ?? [];
    return (list as List).map((e) => Lesson.fromJson(e)).toList();
  }

  Future<void> publishCourse(String id) async {
    await _api.put('/admin/courses/$id', data: {'is_published': true});
  }

  Future<void> unpublishCourse(String id) async {
    await _api.put('/admin/courses/$id', data: {'is_published': false});
  }

  Future<void> deleteCourse(String id) async {
    await _api.delete('/admin/courses/$id');
  }
}
