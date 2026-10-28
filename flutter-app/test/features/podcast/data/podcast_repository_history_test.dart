import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/podcast/data/repositories/podcast_repository.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:shared_preferences/shared_preferences.dart';

PodcastEpisode _episode(String guid) => PodcastEpisode(
  guid: guid,
  title: 'Episode $guid',
  audioUrl: 'https://x/$guid.mp3',
  durationSeconds: 600,
  feedUrl: 'feed://a',
);

ListeningHistory _entry(
  String guid, {
  int position = 120,
  bool completed = false,
  int minute = 0,
  bool snapshot = true,
}) => ListeningHistory(
  episodeGuid: guid,
  feedUrl: 'feed://a',
  lastPositionSeconds: position,
  durationSeconds: 600,
  completed: completed,
  updatedAt: DateTime(2026, 10, 23, 8, minute),
  episode: snapshot ? _episode(guid) : null,
  podcastTitle: 'Show',
);

void main() {
  late PodcastRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = PodcastRepository();
  });

  test('nothing recorded yet reads as empty / null', () async {
    expect(await repo.getRecentListening(), isEmpty);
    expect(await repo.getListeningHistory('g1'), isNull);
    expect(await repo.getContinueListening(), isEmpty);
  });

  test('save then read returns the record, snapshot included', () async {
    await repo.saveListeningHistory(_entry('g1', position: 77));
    final back = await repo.getListeningHistory('g1');
    expect(back?.lastPositionSeconds, 77);
    expect(back?.episode?.title, 'Episode g1');
    expect(back?.podcastTitle, 'Show');
  });

  test('saving the same episode replaces it instead of duplicating', () async {
    await repo.saveListeningHistory(_entry('g1', position: 30));
    await repo.saveListeningHistory(_entry('g1', position: 90, minute: 5));
    final all = await repo.getRecentListening();
    expect(all, hasLength(1));
    expect(all.single.lastPositionSeconds, 90);
  });

  test('most recently updated comes first', () async {
    await repo.saveListeningHistory(_entry('old', minute: 1));
    await repo.saveListeningHistory(_entry('new', minute: 9));
    await repo.saveListeningHistory(_entry('mid', minute: 4));
    expect((await repo.getRecentListening()).map((h) => h.episodeGuid), [
      'new',
      'mid',
      'old',
    ]);
  });

  test('keeps only the newest historyCap entries', () async {
    for (var i = 0; i < PodcastRepository.historyCap + 5; i++) {
      await repo.saveListeningHistory(_entry('g$i', minute: i));
    }
    final all = await repo.getRecentListening();
    expect(all, hasLength(PodcastRepository.historyCap));
    expect(all.first.episodeGuid, 'g${PodcastRepository.historyCap + 4}');
    expect(all.any((h) => h.episodeGuid == 'g0'), isFalse);
  });

  group('getContinueListening', () {
    test('drops finished, barely-started and snapshot-less entries', () async {
      await repo.saveListeningHistory(_entry('keep', minute: 5));
      await repo.saveListeningHistory(
        _entry('done', completed: true, position: 590, minute: 6),
      );
      await repo.saveListeningHistory(_entry('tiny', position: 4, minute: 7));
      await repo.saveListeningHistory(
        _entry('legacy', snapshot: false, minute: 8),
      );
      expect((await repo.getContinueListening()).map((h) => h.episodeGuid), [
        'keep',
      ]);
    });

    test('honours the limit', () async {
      for (var i = 0; i < 8; i++) {
        await repo.saveListeningHistory(_entry('g$i', minute: i));
      }
      expect(await repo.getContinueListening(limit: 3), hasLength(3));
    });
  });

  test('removeListeningHistory forgets only that episode', () async {
    await repo.saveListeningHistory(_entry('a', minute: 1));
    await repo.saveListeningHistory(_entry('b', minute: 2));
    await repo.removeListeningHistory('a');
    expect((await repo.getRecentListening()).map((h) => h.episodeGuid), ['b']);
  });

  test('one corrupt stored entry does not hide the rest', () async {
    SharedPreferences.setMockInitialValues({
      'podcast_listening_history': [
        'not json at all',
        '{"episode_guid":"ok","feed_url":"f","last_position_seconds":50,'
            '"updated_at":"2026-10-23T08:00:00.000"}',
      ],
    });
    final all = await PodcastRepository().getRecentListening();
    expect(all.map((h) => h.episodeGuid), ['ok']);
  });
}
