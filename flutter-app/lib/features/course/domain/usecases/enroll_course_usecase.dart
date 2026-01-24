import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

class EnrollCourseUseCase {
  final CourseRepository repository;

  EnrollCourseUseCase(this.repository);

  Future<bool> call(int courseId) async {
    return await repository.enrollCourse(courseId);
  }
}
