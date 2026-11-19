// ignore_for_file: unused_import
// Only loadLibrary() is used, which the analyzer does not count as a use.
import 'dart:async';

import 'package:lexilingo_app/features/games/presentation/screens/games_hub_screen.dart'
    deferred as games_hub;
import 'package:lexilingo_app/features/home/presentation/pages/today_plan_page.dart'
    deferred as today_plan;
import 'package:lexilingo_app/features/news/presentation/screens/news_detail_screen.dart'
    deferred as news_detail;
import 'package:lexilingo_app/features/news/presentation/screens/news_list_screen.dart'
    deferred as news_list;
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_detail_screen.dart'
    deferred as pod_detail;
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_explore_screen.dart'
    deferred as pod_explore;
import 'package:lexilingo_app/features/vocabulary/presentation/screens/word_of_day_screen.dart'
    deferred as word_of_day;
import 'package:lexilingo_app/features/youtube/presentation/screens/youtube_explore_screen.dart'
    deferred as yt_explore;

bool _scheduled = false;

/// Fetches the chunks of the commonly opened deferred screens once the app is
/// idle, so their first open does not wait on the network. Admin, IELTS and
/// the level tests are left on demand. Failures are ignored: opening the
/// screen loads (and retries) the chunk itself.
void prefetchDeferredFeatures({
  required bool Function() isSignedIn,
  Duration delay = const Duration(seconds: 5),
  List<Future<void> Function()>? loaders,
}) {
  if (_scheduled) return;
  _scheduled = true;
  Timer(delay, () async {
    if (!isSignedIn()) {
      _scheduled = false;
      return;
    }
    for (final load in loaders ?? _defaultLoaders) {
      try {
        await load();
      } catch (_) {}
    }
  });
}

final List<Future<void> Function()> _defaultLoaders = [
  today_plan.loadLibrary,
  word_of_day.loadLibrary,
  games_hub.loadLibrary,
  news_list.loadLibrary,
  pod_explore.loadLibrary,
  yt_explore.loadLibrary,
  news_detail.loadLibrary,
  pod_detail.loadLibrary,
];
