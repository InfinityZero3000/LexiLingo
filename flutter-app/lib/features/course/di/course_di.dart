import 'package:lexilingo_app/core/di/service_locator.dart';
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

/// Register Course Module
/// Phase 2 implementation with backend API integration
void registerCourseModule({required bool skipDatabase}) {
  // Data Sources
  sl.registerLazySingleton<CourseBackendDataSource>(
    () => CourseBackendDataSourceImpl(apiClient: sl<ApiClient>()),
  );

  // Repositories
  sl.registerLazySingleton<CourseRepository>(
    () => CourseRepositoryImpl(backendDataSource: sl<CourseBackendDataSource>()),
  );

  // Use Cases
  sl.registerLazySingleton(() => GetCoursesUseCase(sl()));
  sl.registerLazySingleton(() => GetCourseDetailUseCase(sl()));
  sl.registerLazySingleton(() => EnrollInCourseUseCase(sl()));
  sl.registerLazySingleton(() => GetCategoriesUseCase(sl()));
  sl.registerLazySingleton(() => GetCoursesByCategoryUseCase(sl()));
  sl.registerLazySingleton(() => GetEnrolledCoursesUseCase(sl()));

  // Providers
  sl.registerFactory(
    () => CourseProvider(
      getCoursesUseCase: sl(),
      getCourseDetailUseCase: sl(),
      enrollInCourseUseCase: sl(),
      getCategoriesUseCase: sl(),
      getCoursesByCategoryUseCase: sl(),
      getEnrolledCoursesUseCase: sl(),
    ),
  );
}

