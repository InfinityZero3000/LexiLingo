import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/onboarding/data/datasources/start_learning_remote_datasource.dart';
import 'package:lexilingo_app/features/onboarding/data/repositories/start_learning_repository_impl.dart';
import 'package:lexilingo_app/features/onboarding/domain/repositories/start_learning_repository.dart';
import 'package:lexilingo_app/features/onboarding/domain/usecases/start_learning_usecase.dart';
import 'package:lexilingo_app/features/onboarding/presentation/providers/start_learning_provider.dart';

void registerOnboardingModule() {
  sl.registerLazySingleton<StartLearningRemoteDataSource>(
    () => StartLearningRemoteDataSourceImpl(apiClient: sl<ApiClient>()),
  );
  sl.registerLazySingleton<StartLearningRepository>(
    () => StartLearningRepositoryImpl(remoteDataSource: sl()),
  );
  sl.registerLazySingleton(() => StartLearningUseCase(sl()));
  sl.registerFactory(() => StartLearningProvider(startLearningUseCase: sl()));
}
