import 'package:sqflite/sqflite.dart';
import '../models/course_enrollment_model.dart';
import '../../../../core/services/database_helper.dart';

abstract class EnrollmentLocalDataSource {
  Future<List<CourseEnrollmentModel>> getEnrolledCourses(String userId);
  Future<CourseEnrollmentModel?> getEnrollment(String userId, int courseId);
  Future<int> enrollInCourse(String userId, int courseId);
  Future<int> updateProgress(String userId, int courseId, double progress);
  Future<int> updateLastAccessed(String userId, int courseId);
  Future<int> markCourseCompleted(String userId, int courseId);
  Future<bool> isEnrolled(String userId, int courseId);
}

class EnrollmentLocalDataSourceImpl implements EnrollmentLocalDataSource {
  final DatabaseHelper databaseHelper;

  EnrollmentLocalDataSourceImpl({required this.databaseHelper});

  @override
  Future<List<CourseEnrollmentModel>> getEnrolledCourses(String userId) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'course_enrollments',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'lastAccessedAt DESC',
    );

    return maps.map((map) => CourseEnrollmentModel.fromJson(map)).toList();
  }

  @override
  Future<CourseEnrollmentModel?> getEnrollment(String userId, int courseId) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'course_enrollments',
      where: 'userId = ? AND courseId = ?',
      whereArgs: [userId, courseId],
    );

    if (maps.isEmpty) {
      return null;
    }

    return CourseEnrollmentModel.fromJson(maps.first);
  }

  @override
  Future<int> enrollInCourse(String userId, int courseId) async {
    final db = await databaseHelper.database;
    
    // Check if already enrolled
    final existing = await getEnrollment(userId, courseId);
    if (existing != null) {
      return 0; // Already enrolled
    }
    
    final enrollment = CourseEnrollmentModel(
      id: 0,
      userId: userId,
      courseId: courseId,
      enrolledAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      currentProgress: 0.0,
    );
    
    return await db.insert(
      'course_enrollments',
      enrollment.toJson(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<int> updateProgress(String userId, int courseId, double progress) async {
    final db = await databaseHelper.database;
    return await db.update(
      'course_enrollments',
      {
        'currentProgress': progress,
        'lastAccessedAt': DateTime.now().toIso8601String(),
      },
      where: 'userId = ? AND courseId = ?',
      whereArgs: [userId, courseId],
    );
  }

  @override
  Future<int> updateLastAccessed(String userId, int courseId) async {
    final db = await databaseHelper.database;
    return await db.update(
      'course_enrollments',
      {'lastAccessedAt': DateTime.now().toIso8601String()},
      where: 'userId = ? AND courseId = ?',
      whereArgs: [userId, courseId],
    );
  }

  @override
  Future<int> markCourseCompleted(String userId, int courseId) async {
    final db = await databaseHelper.database;
    return await db.update(
      'course_enrollments',
      {
        'completedAt': DateTime.now().toIso8601String(),
        'currentProgress': 1.0,
      },
      where: 'userId = ? AND courseId = ?',
      whereArgs: [userId, courseId],
    );
  }

  @override
  Future<bool> isEnrolled(String userId, int courseId) async {
    final enrollment = await getEnrollment(userId, courseId);
    return enrollment != null;
  }
}
