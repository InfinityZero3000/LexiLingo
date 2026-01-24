import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/features/course/data/datasources/course_local_data_source.dart';
import 'package:lexilingo_app/features/course/data/repositories/course_repository_impl.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_course_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_featured_courses_usecase.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';

void registerCourseModule({required bool skipDatabase}) {
  if (!skipDatabase) {
    sl.registerLazySingleton<CourseLocalDataSource>(
      () => CourseLocalDataSource(dbHelper: sl<DatabaseHelper>()),
    );
  }

  sl.registerLazySingleton<CourseRepository>(
    () => CourseRepositoryImpl(localDataSource: skipDatabase ? null : sl()),
  );

  sl.registerLazySingleton(() => GetCoursesUseCase(sl()));
  sl.registerLazySingleton(() => GetFeaturedCoursesUseCase(sl()));
  sl.registerLazySingleton(() => GetEnrolledCoursesUseCase(sl()));
  sl.registerLazySingleton(() => EnrollCourseUseCase(sl()));

  sl.registerFactory(
    () => CourseProvider(getCoursesUseCase: sl()),
  );
}
