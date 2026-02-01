import 'package:get_it/get_it.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/course/data/datasources/course_backend_datasource.dart';
import 'package:lexilingo_app/features/course/data/repositories/course_repository_impl.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_course_detail_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_in_course_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_categories_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_by_category_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';

/// Course Feature Dependency Injection
/// Registers all course-related dependencies with GetIt
void setupCourseDependencies(GetIt sl) {
  // Data Sources
  sl.registerLazySingleton<CourseBackendDataSource>(
    () => CourseBackendDataSourceImpl(apiClient: sl<ApiClient>()),
  );

  // Repositories
  sl.registerLazySingleton<CourseRepository>(
    () => CourseRepositoryImpl(backendDataSource: sl<CourseBackendDataSource>()),
  );

  // Use Cases
  sl.registerLazySingleton(() => GetCoursesUseCase(sl<CourseRepository>()));
  sl.registerLazySingleton(() => GetCourseDetailUseCase(sl<CourseRepository>()));
  sl.registerLazySingleton(() => EnrollInCourseUseCase(sl<CourseRepository>()));
  sl.registerLazySingleton(() => GetCategoriesUseCase(sl<CourseRepository>()));
  sl.registerLazySingleton(() => GetCoursesByCategoryUseCase(sl<CourseRepository>()));
  sl.registerLazySingleton(() => GetEnrolledCoursesUseCase(sl<CourseRepository>()));

  // Providers
  sl.registerFactory(
    () => CourseProvider(
      getCoursesUseCase: sl<GetCoursesUseCase>(),
      getCourseDetailUseCase: sl<GetCourseDetailUseCase>(),
      enrollInCourseUseCase: sl<EnrollInCourseUseCase>(),
      getCategoriesUseCase: sl<GetCategoriesUseCase>(),
      getCoursesByCategoryUseCase: sl<GetCoursesByCategoryUseCase>(),
      getEnrolledCoursesUseCase: sl<GetEnrolledCoursesUseCase>(),
    ),
  );
}
