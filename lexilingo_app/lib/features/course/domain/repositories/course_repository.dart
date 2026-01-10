import 'package:lexilingo_app/features/course/domain/entities/course.dart';

abstract class CourseRepository {
  Future<List<Course>> getCourses();
}
