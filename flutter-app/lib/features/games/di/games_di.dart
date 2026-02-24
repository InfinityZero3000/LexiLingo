import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/games/data/repositories/games_repository.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';

/// Register Games feature dependencies.
///
/// Phase 3: English Games + XP System.
void registerGamesModule() {
  // Repository
  sl.registerLazySingleton<GamesRepository>(
    () => GamesRepository(apiClient: sl()),
  );

  // Provider
  sl.registerFactory<GamesProvider>(
    () => GamesProvider(repository: sl<GamesRepository>()),
  );
}
