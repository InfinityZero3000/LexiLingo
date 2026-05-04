import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/social/data/datasources/social_remote_datasource.dart';
import 'package:lexilingo_app/features/social/data/repositories/social_repository.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';

/// Register Social dependencies (Friends, Activity Feed)
void registerSocialModule() {
  if (!sl.isRegistered<SocialRemoteDataSource>()) {
    sl.registerLazySingleton<SocialRemoteDataSource>(
      () => SocialRemoteDataSource(apiClient: sl<ApiClient>()),
    );
  }

  if (!sl.isRegistered<SocialRepository>()) {
    sl.registerLazySingleton<SocialRepository>(
      () => SocialRepository(remote: sl<SocialRemoteDataSource>()),
    );
  }

  if (!sl.isRegistered<SocialProvider>()) {
    sl.registerLazySingleton<SocialProvider>(
      () => SocialProvider(repository: sl<SocialRepository>()),
    );
  }
}
