import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

class GetCoursesUseCase implements UseCase<List<Course>, NoParams> {
  final CourseRepository repository;

  GetCoursesUseCase(this.repository);

  @override
  Future<List<Course>> call(NoParams params) async {
    return await repository.getCourses();
  }
}
