import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

/// Register Gamification dependencies (Shop, Wallet, Leaderboard)
void registerGamificationModule() {
  // Provider (lazily loaded singleton)
  if (!sl.isRegistered<GamificationProvider>()) {
    sl.registerLazySingleton<GamificationProvider>(() => GamificationProvider());
  }
}
