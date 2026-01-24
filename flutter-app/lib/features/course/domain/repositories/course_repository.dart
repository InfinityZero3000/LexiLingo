import 'package:lexilingo_app/features/course/domain/entities/course.dart';

abstract class CourseRepository {
  Future<List<Course>> getAllCourses();
  Future<List<Course>> getFeaturedCourses();
  Future<List<Course>> getCoursesByCategory(String category);
  Future<List<Course>> getEnrolledCourses();
  Future<Course?> getCourseById(int id);
  Future<bool> enrollCourse(int id);
  Future<bool> updateCourseProgress(int id, double progress);
}

