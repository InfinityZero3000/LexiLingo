import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';

ListeningHistory _h({
  int position = 0,
  int duration = 0,
  bool completed = false,
  PodcastEpisode? episode,
}) => ListeningHistory(
  episodeGuid: 'g1',
  feedUrl: 'feed://a',
  lastPositionSeconds: position,
  durationSeconds: duration,
  completed: completed,
  updatedAt: DateTime(2026, 10, 23),
  episode: episode,
);

void main() {
  test('round-trips the episode snapshot and labels through JSON', () {
    const episode = PodcastEpisode(
      guid: 'g1',
      title: 'Ep 1',
      audioUrl: 'https://x/a.mp3',
      durationSeconds: 600,
      feedUrl: 'feed://a',
      cefrLevel: 'B1',
    );
    final original = ListeningHistory(
      episodeGuid: 'g1',
      feedUrl: 'feed://a',
      lastPositionSeconds: 120,
      totalListenedSeconds: 130,
      durationSeconds: 600,
      updatedAt: DateTime(2026, 10, 23, 8),
      episode: episode,
      podcastTitle: 'Show',
      artworkUrl: 'https://x/art.png',
    );

    final back = ListeningHistory.fromJson(original.toJson());

    expect(back.episode?.title, 'Ep 1');
    expect(back.episode?.audioUrl, 'https://x/a.mp3');
    expect(back.podcastTitle, 'Show');
    expect(back.artworkUrl, 'https://x/art.png');
    expect(back.durationSeconds, 600);
    expect(back.lastPositionSeconds, 120);
    expect(back.totalListenedSeconds, 130);
  });

  test('a record saved before snapshots existed still parses', () {
    final legacy = ListeningHistory.fromJson({
      'episode_guid': 'g1',
      'feed_url': 'feed://a',
      'last_position_seconds': 40,
      'updated_at': '2026-10-01T00:00:00.000',
    });
    expect(legacy.episode, isNull);
    expect(legacy.podcastTitle, '');
    expect(legacy.durationSeconds, 0);
  });

  group('progress / minutesLeft', () {
    test('progress is the heard share, clamped to 0..1', () {
      expect(_h(position: 150, duration: 600).progress, 0.25);
      expect(_h(position: 900, duration: 600).progress, 1.0);
    });

    test('unknown length means no progress and no minutes', () {
      expect(_h(position: 50).progress, 0.0);
      expect(_h(position: 50).minutesLeft, isNull);
    });

    test('minutesLeft rounds up and is null once nothing is left', () {
      expect(_h(position: 0, duration: 600).minutesLeft, 10);
      expect(_h(position: 541, duration: 600).minutesLeft, 1);
      expect(_h(position: 600, duration: 600).minutesLeft, isNull);
    });
  });

  group('resumeFromSeconds', () {
    test('resumes a started, unfinished episode at its saved place', () {
      expect(_h(position: 95).resumeFromSeconds, 95);
    });

    test('starts from the top when barely begun or finished', () {
      expect(_h(position: 5).resumeFromSeconds, isNull);
      expect(_h(position: 0).resumeFromSeconds, isNull);
      expect(_h(position: 500, completed: true).resumeFromSeconds, isNull);
    });
  });
}
