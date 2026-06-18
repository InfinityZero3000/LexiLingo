import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/gamification/data/datasources/gamification_remote_data_source.dart';
import 'package:lexilingo_app/features/gamification/data/repositories/gamification_repository_impl.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

void registerGamificationModule() {
  if (!sl.isRegistered<GamificationRemoteDataSource>()) {
    sl.registerLazySingleton<GamificationRemoteDataSource>(
      () => GamificationRemoteDataSourceImpl(sl<ApiClient>()),
    );
  }

  if (!sl.isRegistered<GamificationRepository>()) {
    sl.registerLazySingleton<GamificationRepository>(
      () => GamificationRepositoryImpl(sl<GamificationRemoteDataSource>()),
    );
  }

  if (!sl.isRegistered<GamificationProvider>()) {
    sl.registerLazySingleton<GamificationProvider>(
      () => GamificationProvider(repository: sl<GamificationRepository>()),
    );
  }
}
