import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

class GetEnrolledCoursesUseCase {
  final CourseRepository repository;

  GetEnrolledCoursesUseCase(this.repository);

  Future<List<Course>> call() async {
    return await repository.getEnrolledCourses();
  }
}
