import 'package:lexilingo_app/features/course/data/datasources/course_local_data_source.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

class CourseRepositoryImpl implements CourseRepository {
  final CourseLocalDataSource localDataSource;

  CourseRepositoryImpl({required this.localDataSource});

  @override
  Future<List<Course>> getCourses() async {
    return await localDataSource.getCourses();
  }
}
