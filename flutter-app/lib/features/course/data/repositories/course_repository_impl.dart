import 'package:lexilingo_app/features/course/data/datasources/course_local_data_source.dart';
import 'package:lexilingo_app/features/course/domain/entities/course.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

class CourseRepositoryImpl implements CourseRepository {
  final CourseLocalDataSource? localDataSource;

  CourseRepositoryImpl({this.localDataSource});

  @override
  Future<List<Course>> getAllCourses() async {
    if (localDataSource == null) {
      return _getMockCourses();
    }
    return await localDataSource!.getAllCourses();
  }

  @override
  Future<List<Course>> getFeaturedCourses() async {
    if (localDataSource == null) {
      return _getMockCourses().where((c) => c.isFeatured).toList();
    }
    return await localDataSource!.getFeaturedCourses();
  }

  @override
  Future<List<Course>> getCoursesByCategory(String category) async {
    if (localDataSource == null) {
      return _getMockCourses().where((c) => c.category == category).toList();
    }
    return await localDataSource!.getCoursesByCategory(category);
  }

  @override
  Future<List<Course>> getEnrolledCourses() async {
    if (localDataSource == null) {
      return [];
    }
    return await localDataSource!.getEnrolledCourses();
  }

  @override
  Future<Course?> getCourseById(int id) async {
    if (localDataSource == null) {
      return _getMockCourses().firstWhere((c) => c.id == id);
    }
    return await localDataSource!.getCourseById(id);
  }

  @override
  Future<bool> enrollCourse(int id) async {
    if (localDataSource == null) {
      return true;
    }
    final result = await localDataSource!.enrollCourse(id);
    return result > 0;
  }

  @override
  Future<bool> updateCourseProgress(int id, double progress) async {
    if (localDataSource == null) {
      return true;
    }
    final result = await localDataSource!.updateCourseProgress(id, progress);
    return result > 0;
  }

  List<Course> _getMockCourses() {
    return [
      Course(
        id: 1,
        title: 'English for Beginners',
        description: 'Start your English learning journey with fundamental vocabulary and grammar.',
        level: 'A1',
        category: 'Language Basics',
        imageUrl: 'https://images.unsplash.com/photo-1546410531-bb4caa6b424d?w=400',
        duration: '4 weeks',
        lessonsCount: 12,
        isFeatured: true,
        rating: 4.5,
        enrolledCount: 1250,
      ),
      Course(
        id: 2,
        title: 'Conversational English',
        description: 'Learn practical English for everyday conversations.',
        level: 'B1',
        category: 'Speaking',
        imageUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=400',
        duration: '6 weeks',
        lessonsCount: 18,
        isFeatured: true,
        rating: 4.7,
        enrolledCount: 980,
      ),
    ];
  }
}

