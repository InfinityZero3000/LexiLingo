import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/progress/data/datasources/progress_remote_datasource.dart';
import 'package:lexilingo_app/features/progress/data/repositories/progress_repository_impl.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/complete_lesson_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_course_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_my_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';

/// Registers all progress-related dependencies
void registerProgressModule() {
  // Provider
  sl.registerFactory<ProgressProvider>(
    () => ProgressProvider(
      getMyProgressUseCase: sl(),
      getCourseProgressUseCase: sl(),
      completeLessonUseCase: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton<GetMyProgressUseCase>(
    () => GetMyProgressUseCase(sl()),
  );
  sl.registerLazySingleton<GetCourseProgressUseCase>(
    () => GetCourseProgressUseCase(sl()),
  );
  sl.registerLazySingleton<CompleteLessonUseCase>(
    () => CompleteLessonUseCase(sl()),
  );

  // Repository
  sl.registerLazySingleton<ProgressRepository>(
    () => ProgressRepositoryImpl(
      remoteDataSource: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<ProgressRemoteDataSource>(
    () => ProgressRemoteDataSourceImpl(
      apiClient: sl(),
    ),
  );
}
