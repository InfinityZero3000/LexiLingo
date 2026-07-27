import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/placement_test_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';

/// Registers all level-related dependencies
void registerLevelModule() {
  // Provider - Factory for fresh instances
  sl.registerFactory<LevelProvider>(
    () => LevelProvider(apiClient: sl<ApiClient>()),
  );

  // Proficiency data source (singleton — stateless HTTP wrapper)
  sl.registerLazySingleton<ProficiencyDataSource>(
    () => ProficiencyDataSource(apiClient: sl<ApiClient>()),
  );

  // Proficiency provider (factory — fresh state per screen lifecycle)
  sl.registerFactory<ProficiencyProvider>(
    () => ProficiencyProvider(dataSource: sl<ProficiencyDataSource>()),
  );

  sl.registerFactory<PlacementTestProvider>(
    () => PlacementTestProvider(dataSource: sl<ProficiencyDataSource>()),
  );
}
