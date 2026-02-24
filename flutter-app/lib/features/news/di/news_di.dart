import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/news/data/repositories/news_repository.dart';
import 'package:lexilingo_app/features/news/presentation/providers/news_provider.dart';

/// Register News feature dependencies.
void registerNewsModule() {
  // Repository
  sl.registerLazySingleton<NewsRepository>(
    () => NewsRepository(),
  );

  // Provider
  sl.registerFactory<NewsProvider>(
    () => NewsProvider(repository: sl<NewsRepository>()),
  );
}
