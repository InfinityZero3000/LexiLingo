import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';

/// Register Social dependencies (Friends, Activity Feed)
void registerSocialModule() {
  // Provider (lazily loaded singleton)
  if (!sl.isRegistered<SocialProvider>()) {
    sl.registerLazySingleton<SocialProvider>(() => SocialProvider());
  }
}
