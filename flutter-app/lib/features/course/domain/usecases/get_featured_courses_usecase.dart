import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

class GetFeaturedCoursesUseCase {
  final CourseRepository repository;

  GetFeaturedCoursesUseCase(this.repository);

  Future<List<Course>> call() async {
    return await repository.getFeaturedCourses();
  }
}
