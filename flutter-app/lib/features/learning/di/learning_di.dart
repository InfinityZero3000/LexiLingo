import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/learning/data/datasources/learning_remote_datasource.dart';
import 'package:lexilingo_app/features/learning/data/repositories/learning_repository_impl.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/start_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/submit_answer_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/complete_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_course_roadmap_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_lesson_content_usecase.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';

/// Register Learning module dependencies
void registerLearningModule() {
  // Data Sources
  sl.registerLazySingleton<LearningRemoteDataSource>(
    () => LearningRemoteDataSourceImpl(apiClient: sl<ApiClient>()),
  );

  // Repositories
  sl.registerLazySingleton<LearningRepository>(
    () => LearningRepositoryImpl(remoteDataSource: sl<LearningRemoteDataSource>()),
  );

  // Use Cases
  sl.registerLazySingleton<StartLessonUseCase>(
    () => StartLessonUseCase(repository: sl<LearningRepository>()),
  );
  sl.registerLazySingleton<SubmitAnswerUseCase>(
    () => SubmitAnswerUseCase(repository: sl<LearningRepository>()),
  );
  sl.registerLazySingleton<CompleteLessonUseCase>(
    () => CompleteLessonUseCase(repository: sl<LearningRepository>()),
  );
  sl.registerLazySingleton<GetCourseRoadmapUseCase>(
    () => GetCourseRoadmapUseCase(repository: sl<LearningRepository>()),
  );
  sl.registerLazySingleton<GetLessonContentUseCase>(
    () => GetLessonContentUseCase(repository: sl<LearningRepository>()),
  );

  // Providers
  sl.registerFactory<LearningProvider>(
    () => LearningProvider(
      startLessonUseCase: sl<StartLessonUseCase>(),
      submitAnswerUseCase: sl<SubmitAnswerUseCase>(),
      completeLessonUseCase: sl<CompleteLessonUseCase>(),
      getCourseRoadmapUseCase: sl<GetCourseRoadmapUseCase>(),
      getLessonContentUseCase: sl<GetLessonContentUseCase>(),
    ),
  );
}

