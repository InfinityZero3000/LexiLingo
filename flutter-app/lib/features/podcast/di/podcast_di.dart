import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/podcast_audio_handler.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';

/// Register Podcast feature dependencies.
///
/// Async because [AudioService.init] must be awaited on mobile/desktop.
/// On web, AudioService is not supported — we skip it to avoid startup hang.
Future<void> registerPodcastModule() async {
  // Repository
  sl.registerLazySingleton<PodcastRepository>(() => PodcastRepository());

  // Provider
  sl.registerFactory<PodcastProvider>(
    () => PodcastProvider(repository: sl<PodcastRepository>()),
  );

  // Background audio handler — mobile/desktop only.
  // Keep initialization non-blocking so app can render first frame immediately.
  if (!kIsWeb) {
    unawaited(_registerPodcastAudioHandler());
  } else {
    // Web fallback: register handler directly bypassing native audio_service initialization.
    if (!sl.isRegistered<PodcastAudioHandler>()) {
      sl.registerSingleton<PodcastAudioHandler>(PodcastAudioHandler());
    }
  }
}

Future<void> _registerPodcastAudioHandler() async {
  try {
    final audioHandler = await AudioService.init<PodcastAudioHandler>(
      builder: () => PodcastAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.lexilingo.podcast.channel',
        androidNotificationChannelName: 'LexiLingo Podcast',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: true,
      ),
    ).timeout(const Duration(seconds: 8));

    if (!sl.isRegistered<PodcastAudioHandler>()) {
      sl.registerSingleton<PodcastAudioHandler>(audioHandler);
    }
  } on MissingPluginException {
    // Native audio plugins unavailable (e.g. unit test environment) — skip.
  } on TimeoutException {
    // Prevent startup deadlock if native audio service is slow/unavailable.
  } catch (_) {
    // Keep podcast audio optional during app bootstrap.
  }
}
