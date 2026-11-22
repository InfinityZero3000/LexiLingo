import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';

PodcastEpisode _episode(String guid) => PodcastEpisode(
  guid: guid,
  title: 'Episode $guid',
  audioUrl: 'https://x/$guid.mp3',
  durationSeconds: 600,
  feedUrl: 'feed://a',
);

ListeningHistory _history(
  String guid, {
  int position = 200,
  bool done = false,
}) => ListeningHistory(
  episodeGuid: guid,
  feedUrl: 'feed://a',
  lastPositionSeconds: position,
  durationSeconds: 600,
  completed: done,
  updatedAt: DateTime(2026, 10, 23),
  episode: _episode(guid),
);

class _Repo extends PodcastRepository {
  _Repo({this.history = const [], this.historyFails = false});

  final List<ListeningHistory> history;
  final bool historyFails;

  @override
  Future<List<PodcastEpisode>> getEpisodes({
    required String feedUrl,
    int limit = 20,
  }) async => [_episode('a'), _episode('b')];

  @override
  Future<List<ListeningHistory>> getRecentListening() async {
    if (historyFails) throw Exception('prefs unavailable');
    return history;
  }

  @override
  Future<List<ListeningHistory>> getContinueListening({int limit = 5}) async =>
      history.where((h) => !h.completed).toList();
}

const _podcast = Podcast(id: '1', title: 'Show', feedUrl: 'feed://a');

void main() {
  stalePodcastTests();

  test('loadEpisodes overlays saved progress on matching episodes', () async {
    final provider = PodcastProvider(
      repository: _Repo(history: [_history('a', position: 250)]),
    );
    await provider.loadEpisodes(_podcast);

    final a = provider.currentEpisodes.firstWhere((e) => e.guid == 'a');
    final b = provider.currentEpisodes.firstWhere((e) => e.guid == 'b');
    expect(a.listenProgress, 250);
    expect(a.isCompleted, isFalse);
    expect(b.listenProgress, 0, reason: 'never played');
  });

  test('a finished episode is marked completed in the list', () async {
    final provider = PodcastProvider(
      repository: _Repo(history: [_history('a', position: 590, done: true)]),
    );
    await provider.loadEpisodes(_podcast);
    expect(
      provider.currentEpisodes.firstWhere((e) => e.guid == 'a').isCompleted,
      isTrue,
    );
  });

  test('a history failure still delivers the episode list', () async {
    final provider = PodcastProvider(repository: _Repo(historyFails: true));
    await provider.loadEpisodes(_podcast);
    expect(provider.error, isNull);
    expect(provider.currentEpisodes, hasLength(2));
  });

  test(
    'loadContinueListening exposes the repository shelf and notifies',
    () async {
      final provider = PodcastProvider(
        repository: _Repo(history: [_history('a'), _history('b', done: true)]),
      );
      var notified = 0;
      provider.addListener(() => notified++);

      expect(provider.continueListening, isEmpty);
      await provider.loadContinueListening();

      expect(provider.continueListening.map((h) => h.episodeGuid), ['a']);
      expect(notified, 1);
    },
  );
}

class _SlowEpisodesRepo extends PodcastRepository {
  final Map<String, Completer<List<PodcastEpisode>>> pending = {};

  @override
  Future<List<PodcastEpisode>> getEpisodes({
    required String feedUrl,
    int limit = 20,
  }) => (pending[feedUrl] = Completer<List<PodcastEpisode>>()).future;

  @override
  Future<List<ListeningHistory>> getRecentListening() async => const [];
}

void stalePodcastTests() {
  test('a slow first podcast cannot overwrite the second one opened', () async {
    final repo = _SlowEpisodesRepo();
    final provider = PodcastProvider(repository: repo);

    final first = provider.loadEpisodes(
      const Podcast(id: '1', title: 'One', feedUrl: 'feed://one'),
    );
    final second = provider.loadEpisodes(
      const Podcast(id: '2', title: 'Two', feedUrl: 'feed://two'),
    );
    repo.pending['feed://two']!.complete([_episode('two')]);
    await second;
    repo.pending['feed://one']!.complete([_episode('one')]);
    await first;

    expect(provider.currentEpisodes.map((e) => e.guid), ['two']);
    expect(provider.isLoading, isFalse);
  });
}
