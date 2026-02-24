import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/youtube/data/repositories/youtube_repository.dart';
import 'package:lexilingo_app/features/youtube/presentation/providers/youtube_provider.dart';

/// Register YouTube feature dependencies.
///
/// Phase 1: YouTube Video Integration.
void registerYouTubeModule() {
  // Repository
  sl.registerLazySingleton<YouTubeRepository>(
    () => YouTubeRepository(),
  );

  // Provider
  sl.registerFactory<YouTubeProvider>(
    () => YouTubeProvider(repository: sl<YouTubeRepository>()),
  );
}
