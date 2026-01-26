import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';

/// Get paginated list of courses
class GetCoursesUseCase implements UseCase<(List<CourseEntity>, int), GetCoursesParams> {
  final CourseRepository repository;

  GetCoursesUseCase(this.repository);

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> call(GetCoursesParams params) async {
    return await repository.getCourses(
      page: params.page,
      pageSize: params.pageSize,
      language: params.language,
      level: params.level,
    );
  }
}

class GetCoursesParams {
  final int page;
  final int pageSize;
  final String? language;
  final String? level;

  const GetCoursesParams({
    this.page = 1,
    this.pageSize = 20,
    this.language,
    this.level,
  });
}
