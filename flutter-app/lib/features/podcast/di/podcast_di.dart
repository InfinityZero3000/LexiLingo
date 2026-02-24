import 'package:audio_service/audio_service.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/podcast_audio_handler.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';

/// Register Podcast feature dependencies.
///
/// Async because [AudioService.init] must be awaited to obtain the
/// concrete [PodcastAudioHandler] singleton registered in GetIt.
Future<void> registerPodcastModule() async {
  // Repository
  sl.registerLazySingleton<PodcastRepository>(
    () => PodcastRepository(),
  );

  // Provider
  sl.registerFactory<PodcastProvider>(
    () => PodcastProvider(repository: sl<PodcastRepository>()),
  );

  // Background audio handler (skill: audio-format-optimization)
  // AudioService.init boots the OS media-session integration and returns
  // the concrete handler instance for use across the app.
  final audioHandler = await AudioService.init<PodcastAudioHandler>(
    builder: () => PodcastAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.lexilingo.podcast.channel',
      androidNotificationChannelName: 'LexiLingo Podcast',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
    ),
  );
  sl.registerSingleton<PodcastAudioHandler>(audioHandler);
}
