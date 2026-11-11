import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/data/services/listening_history_recorder.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';

class _MemoryRepo extends PodcastRepository {
  final saved = <ListeningHistory>[];
  final existing = <String, ListeningHistory>{};

  @override
  Future<ListeningHistory?> getListeningHistory(String episodeGuid) async =>
      existing[episodeGuid];

  @override
  Future<void> saveListeningHistory(ListeningHistory history) async =>
      saved.add(history);
}

PodcastEpisode _episode(String guid, {int duration = 100}) => PodcastEpisode(
  guid: guid,
  title: 'Episode $guid',
  audioUrl: 'https://x/$guid.mp3',
  durationSeconds: duration,
  feedUrl: 'feed://a',
);

Duration _s(int s) => Duration(seconds: s);

void main() {
  late _MemoryRepo repo;
  late ListeningHistoryRecorder recorder;

  setUp(() {
    repo = _MemoryRepo();
    recorder = ListeningHistoryRecorder(
      repo,
      now: () => DateTime(2026, 10, 23),
    );
  });

  void start({String guid = 'g1', int duration = 100}) {
    recorder.track(
      episode: _episode(guid, duration: duration),
      podcastTitle: 'Show',
      artworkUrl: 'https://x/art.png',
    );
    recorder.onPlaying(true);
  }

  test('records nothing until an episode is tracked', () async {
    recorder
      ..onPlaying(true)
      ..onPosition(_s(30))
      ..onPlaying(false);
    await recorder.flush();
    expect(repo.saved, isEmpty);
  });

  test('throttles saves while playing to one per saveEvery', () async {
    start();
    for (var t = 0; t <= 4; t++) {
      recorder.onPosition(_s(t));
    }
    await recorder.flush();
    expect(repo.saved, isEmpty, reason: 'under 5s of progress');

    recorder.onPosition(_s(5));
    await recorder.flush();
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.lastPositionSeconds, 5);

    for (var t = 6; t <= 9; t++) {
      recorder.onPosition(_s(t));
    }
    await recorder.flush();
    expect(repo.saved, hasLength(1), reason: 'next save only at +5s');

    recorder.onPosition(_s(10));
    await recorder.flush();
    expect(repo.saved, hasLength(2));
  });

  test('pausing saves immediately, with the snapshot and labels', () async {
    start();
    recorder
      ..onPosition(_s(2))
      ..onPlaying(false);
    await recorder.flush();

    final h = repo.saved.single;
    expect(h.lastPositionSeconds, 2);
    expect(h.episode?.guid, 'g1');
    expect(h.podcastTitle, 'Show');
    expect(h.artworkUrl, 'https://x/art.png');
    expect(h.updatedAt, DateTime(2026, 10, 23));
  });

  test('a position tick while paused does not write', () async {
    start();
    recorder.onPlaying(false);
    await recorder.flush();
    final before = repo.saved.length;
    recorder.onPosition(_s(50));
    recorder.onPosition(_s(60));
    await recorder.flush();
    expect(repo.saved.length, before);
  });

  test('completed flips at 80% of the duration', () async {
    start(duration: 100);
    recorder
      ..onPosition(_s(79))
      ..onPlaying(false);
    await recorder.flush();
    expect(repo.saved.last.completed, isFalse);
    expect(repo.saved.last.completedAt, isNull);

    recorder.onPlaying(true);
    recorder
      ..onPosition(_s(80))
      ..onPlaying(false);
    await recorder.flush();
    expect(repo.saved.last.completed, isTrue);
    expect(repo.saved.last.completedAt, DateTime(2026, 10, 23));
  });

  test('a duration learned from the player beats the feed value', () async {
    start(duration: 0);
    recorder
      ..onDuration(_s(200))
      ..onPosition(_s(150))
      ..onPlaying(false);
    await recorder.flush();
    expect(repo.saved.last.durationSeconds, 200);
    expect(repo.saved.last.completed, isFalse);
  });

  group('time listened', () {
    test('counts steady playback but not seeks', () async {
      start();
      for (final t in [1, 2, 3]) {
        recorder.onPosition(_s(t));
      }
      recorder.onPosition(_s(60)); // a seek, not 57s of listening
      recorder.onPosition(_s(61));
      recorder.onPlaying(false);
      await recorder.flush();
      expect(repo.saved.last.totalListenedSeconds, 4);
    });

    test('does not count a seek made while paused', () async {
      start();
      recorder
        ..onPosition(_s(1))
        ..onPlaying(false)
        ..onPosition(_s(40))
        ..onPlaying(true)
        ..onPosition(_s(41))
        ..onPlaying(false);
      await recorder.flush();
      expect(repo.saved.last.totalListenedSeconds, 2);
    });

    test('carries on from the total already stored for the episode', () async {
      repo.existing['g1'] = ListeningHistory(
        episodeGuid: 'g1',
        feedUrl: 'feed://a',
        totalListenedSeconds: 100,
        updatedAt: DateTime(2026, 10, 1),
      );
      start();
      await recorder.flush();
      recorder
        ..onPosition(_s(1))
        ..onPosition(_s(2))
        ..onPlaying(false);
      await recorder.flush();
      expect(repo.saved.last.totalListenedSeconds, 102);
    });
  });

  group('tracking', () {
    test('re-tracking the same episode keeps its running state', () async {
      start();
      recorder
        ..onPosition(_s(1))
        ..onPosition(_s(2));
      recorder.track(
        episode: _episode('g1'),
        podcastTitle: 'Renamed',
        artworkUrl: 'https://x/new.png',
      );
      recorder
        ..onPosition(_s(3))
        ..onPlaying(false);
      await recorder.flush();
      expect(repo.saved.last.totalListenedSeconds, 3);
      expect(repo.saved.last.podcastTitle, 'Renamed');
    });

    test('switching episode starts a fresh count and a fresh place', () async {
      start(guid: 'a');
      recorder
        ..onPosition(_s(1))
        ..onPosition(_s(2))
        ..onPlaying(false);
      await recorder.flush();

      recorder.track(
        episode: _episode('b'),
        podcastTitle: 'Show',
        artworkUrl: '',
      );
      recorder
        ..onPlaying(true)
        ..onPosition(_s(1))
        ..onPlaying(false);
      await recorder.flush();

      expect(repo.saved.last.episodeGuid, 'b');
      expect(repo.saved.last.totalListenedSeconds, 1);
      expect(repo.saved.last.lastPositionSeconds, 1);
    });
  });

  group('bind', () {
    test('feeds stream events through and ignores a repeat bind', () async {
      final position = StreamController<Duration>.broadcast(sync: true);
      final duration = StreamController<Duration?>.broadcast(sync: true);
      final playing = StreamController<bool>.broadcast(sync: true);
      final owner = Object();

      void bind() => recorder.bind(
        owner: owner,
        position: position.stream,
        duration: duration.stream,
        playing: playing.stream,
      );
      bind();
      bind(); // the player screen reopening
      expect(position.hasListener, isTrue);

      recorder.track(
        episode: _episode('g1', duration: 0),
        podcastTitle: 'Show',
        artworkUrl: '',
      );
      duration.add(_s(300));
      playing.add(true);
      position.add(_s(1));
      position.add(_s(2));
      playing.add(false);
      await recorder.flush();

      expect(repo.saved, hasLength(1), reason: 'one subscription, one save');
      expect(repo.saved.single.durationSeconds, 300);
      expect(repo.saved.single.lastPositionSeconds, 2);
    });
  });
}
