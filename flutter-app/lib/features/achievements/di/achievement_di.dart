import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/achievements/data/datasources/achievement_remote_datasource.dart';
import 'package:lexilingo_app/features/achievements/data/repositories/achievement_repository_impl.dart';
import 'package:lexilingo_app/features/achievements/domain/repositories/achievement_repository.dart';
import 'package:lexilingo_app/features/achievements/domain/usecases/get_recent_badges_usecase.dart';
import 'package:lexilingo_app/features/achievements/presentation/providers/achievement_provider.dart';

/// Registers all achievement-related dependencies
/// 
/// Following agent-skills/gamification-achievement-badges pattern:
/// Meaningful achievement system with tiered badges for 25-40% engagement boost
void registerAchievementModule() {
  // Use Cases
  sl.registerFactory<GetRecentBadgesUseCase>(
    () => GetRecentBadgesUseCase(repository: sl()),
  );

  // Provider - Factory for fresh instances
  sl.registerFactory<AchievementProvider>(
    () => AchievementProvider(
      repository: sl(),
    ),
  );

  // Repository - Singleton
  sl.registerLazySingleton<AchievementRepository>(
    () => AchievementRepositoryImpl(
      remoteDataSource: sl(),
    ),
  );

  // Data sources - Singleton
  sl.registerLazySingleton<AchievementRemoteDataSource>(
    () => AchievementRemoteDataSourceImpl(
      apiClient: sl(),
    ),
  );
}
