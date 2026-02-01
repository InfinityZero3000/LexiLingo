import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';

/// Registers all level-related dependencies
void registerLevelModule() {
  // Provider - Factory for fresh instances
  sl.registerFactory<LevelProvider>(
    () => LevelProvider(),
  );
}
