import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/features/course/data/models/course_model.dart';

class CourseLocalDataSource {
  final DatabaseHelper dbHelper;

  CourseLocalDataSource({required this.dbHelper});

  Future<List<CourseModel>> getAllCourses() async {
    final db = await dbHelper.database;
    final result = await db.query('courses', orderBy: 'createdAt DESC');
    
    return result.map((json) => CourseModel.fromJson(json)).toList();
  }

  Future<List<CourseModel>> getFeaturedCourses() async {
    final db = await dbHelper.database;
    final result = await db.query(
      'courses',
      where: 'isFeatured = ?',
      whereArgs: [1],
      orderBy: 'rating DESC',
    );
    
    return result.map((json) => CourseModel.fromJson(json)).toList();
  }

  Future<List<CourseModel>> getCoursesByCategory(String category) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'courses',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'rating DESC',
    );
    
    return result.map((json) => CourseModel.fromJson(json)).toList();
  }

  Future<List<CourseModel>> getEnrolledCourses() async {
    final db = await dbHelper.database;
    final result = await db.query(
      'courses',
      where: 'isEnrolled = ?',
      whereArgs: [1],
      orderBy: 'updatedAt DESC',
    );
    
    return result.map((json) => CourseModel.fromJson(json)).toList();
  }

  Future<CourseModel?> getCourseById(int id) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'courses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    
    if (result.isEmpty) return null;
    return CourseModel.fromJson(result.first);
  }

  Future<int> insertCourse(CourseModel course) async {
    final db = await dbHelper.database;
    return await db.insert('courses', course.toJson());
  }

  Future<int> updateCourse(CourseModel course) async {
    final db = await dbHelper.database;
    return await db.update(
      'courses',
      course.toJson(),
      where: 'id = ?',
      whereArgs: [course.id],
    );
  }

  Future<int> deleteCourse(int id) async {
    final db = await dbHelper.database;
    return await db.delete(
      'courses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> enrollCourse(int id) async {
    final db = await dbHelper.database;
    return await db.update(
      'courses',
      {
        'isEnrolled': 1,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateCourseProgress(int id, double progress) async {
    final db = await dbHelper.database;
    return await db.update(
      'courses',
      {
        'progress': progress,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

