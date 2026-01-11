import 'package:lexilingo_app/features/course/data/datasources/course_local_data_source.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

class CourseRepositoryImpl implements CourseRepository {
  final CourseLocalDataSource? localDataSource;

  CourseRepositoryImpl({this.localDataSource});

  @override
  Future<List<Course>> getCourses() async {
    if (localDataSource == null) {
      // Return mock data for web
      return [
        Course(
          id: 1,
          title: 'Beginner English',
          description: 'Start your journey here.',
          level: 'A1',
          progress: 0.0,
        ),
        Course(
          id: 2,
          title: 'Intermediate Conversation',
          description: 'Speak with confidence.',
          level: 'B1',
          progress: 0.0,
        ),
      ];
    }
    return await localDataSource!.getCourses();
  }
}
