import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';

class CourseLocalDataSource {
  final DatabaseHelper dbHelper;

  CourseLocalDataSource({required this.dbHelper});

  Future<List<Course>> getCourses() async {
    final db = await dbHelper.database;
    final result = await db.query('courses');
    
    // Map DB result to Entity
    return result.map((e) => Course(
      id: e['id'] as int?,
      title: e['title'] as String,
      description: e['description'] as String,
      level: e['level'] as String,
      progress: (e['progress'] as num).toDouble(),
    )).toList();
  }
}
