import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';

void main() {
  // ── DownloadState ───────────────────────────────────────────────────────────

  group('DownloadState', () {
    test('has three values', () {
      expect(DownloadState.values.length, 3);
    });

    test('values are notDownloaded, downloading, downloaded', () {
      expect(DownloadState.values, contains(DownloadState.notDownloaded));
      expect(DownloadState.values, contains(DownloadState.downloading));
      expect(DownloadState.values, contains(DownloadState.downloaded));
    });

    test('name property returns snake_case string', () {
      expect(DownloadState.notDownloaded.name, 'notDownloaded');
      expect(DownloadState.downloading.name, 'downloading');
      expect(DownloadState.downloaded.name, 'downloaded');
    });
  });

  // ── Podcast ─────────────────────────────────────────────────────────────────

  group('Podcast', () {
    final sampleJson = <String, dynamic>{
      'id': 'pod001',
      'title': 'BBC 6 Minute English',
      'author': 'BBC Learning English',
      'description': 'Short English lessons for learners.',
      'feed_url': 'https://feeds.megaphone.fm/bbclearningenglish',
      'artwork_url': 'https://example.com/artwork.jpg',
      'episode_count': 150,
      'categories': ['education', 'learning'],
      'cefr_level': 'A2',
      'language': 'en',
      'is_followed': false,
    };

    test('fromJson parses all fields correctly', () {
      final podcast = Podcast.fromJson(sampleJson);
      expect(podcast.id, 'pod001');
      expect(podcast.title, 'BBC 6 Minute English');
      expect(podcast.author, 'BBC Learning English');
      expect(podcast.feedUrl, 'https://feeds.megaphone.fm/bbclearningenglish');
      expect(podcast.cefrLevel, 'A2');
      expect(podcast.language, 'en');
      expect(podcast.episodeCount, 150);
      expect(podcast.isFollowed, false);
    });

    test('fromJson parses categories list', () {
      final podcast = Podcast.fromJson(sampleJson);
      expect(podcast.categories, ['education', 'learning']);
    });

    test('fromJson defaults cefr_level to B1 when missing', () {
      final podcast = Podcast.fromJson(<String, dynamic>{
        'id': '1',
        'title': 'Test',
        'feed_url': 'https://example.com/feed.rss',
      });
      expect(podcast.cefrLevel, 'B1');
    });

    test('fromJson defaults isFollowed to false', () {
      final podcast = Podcast.fromJson(<String, dynamic>{
        'id': '1',
        'title': 'Test',
        'feed_url': 'https://example.com/feed.rss',
      });
      expect(podcast.isFollowed, false);
    });

    test('fromJson defaults language to en', () {
      final podcast = Podcast.fromJson(<String, dynamic>{
        'id': '1',
        'title': 'Test',
        'feed_url': 'https://example.com/feed.rss',
      });
      expect(podcast.language, 'en');
    });

    test('toJson roundtrip preserves all fields', () {
      final podcast = Podcast.fromJson(sampleJson);
      final json = podcast.toJson();
      expect(json['id'], 'pod001');
      expect(json['title'], 'BBC 6 Minute English');
      expect(json['feed_url'], 'https://feeds.megaphone.fm/bbclearningenglish');
      expect(json['cefr_level'], 'A2');
      expect(json['episode_count'], 150);
    });

    test('copyWith changes isFollowed', () {
      final podcast = Podcast.fromJson(sampleJson);
      final followed = podcast.copyWith(isFollowed: true);
      expect(followed.isFollowed, true);
      expect(followed.id, podcast.id);
      expect(followed.title, podcast.title);
    });

    test('copyWith without args preserves all fields', () {
      final podcast = Podcast.fromJson(sampleJson);
      final copy = podcast.copyWith();
      expect(copy.id, podcast.id);
      expect(copy.isFollowed, podcast.isFollowed);
    });
  });

  // ── PodcastEpisode ──────────────────────────────────────────────────────────

  group('PodcastEpisode', () {
    final sampleJson = <String, dynamic>{
      'guid': 'ep-001',
      'title': 'Episode 1: Greetings',
      'audio_url': 'https://example.com/ep1.mp3',
      'duration_seconds': 360,
      'published_at': '2024-01-15T10:00:00Z',
      'description': 'Learn how to greet people in English',
      'episode_number': 1,
      'image_url': 'https://example.com/ep1.jpg',
      'cefr_level': 'A1',
      'feed_url': 'https://example.com/feed.rss',
      'listen_progress': 0,
      'is_completed': false,
      'download_state': 'notDownloaded',
    };

    test('fromJson parses all fields correctly', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      expect(ep.guid, 'ep-001');
      expect(ep.title, 'Episode 1: Greetings');
      expect(ep.audioUrl, 'https://example.com/ep1.mp3');
      expect(ep.durationSeconds, 360);
      expect(ep.episodeNumber, 1);
      expect(ep.cefrLevel, 'A1');
      expect(ep.feedUrl, 'https://example.com/feed.rss');
    });

    test('fromJson defaults download state to notDownloaded', () {
      final ep = PodcastEpisode.fromJson(<String, dynamic>{
        'guid': 'ep1',
        'title': 'Test',
        'audio_url': '',
        'feed_url': 'https://example.com/feed.rss',
      });
      expect(ep.downloadState, DownloadState.notDownloaded);
    });

    test('fromJson parses downloading state', () {
      final ep = PodcastEpisode.fromJson({
        ...sampleJson,
        'download_state': 'downloading',
      });
      expect(ep.downloadState, DownloadState.downloading);
    });

    test('fromJson parses downloaded state', () {
      final ep = PodcastEpisode.fromJson({
        ...sampleJson,
        'download_state': 'downloaded',
        'local_path': '/storage/ep1.mp3',
      });
      expect(ep.downloadState, DownloadState.downloaded);
      expect(ep.localPath, '/storage/ep1.mp3');
    });

    test('fromJson defaults isCompleted to false', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      expect(ep.isCompleted, false);
    });

    test('fromJson defaults listenProgress to 0', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      expect(ep.listenProgress, 0);
    });

    test('toJson includes download_state as string', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      final json = ep.toJson();
      expect(json['download_state'], 'notDownloaded');
    });

    test('toJson roundtrip preserves guid and audio_url', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      final json = ep.toJson();
      expect(json['guid'], 'ep-001');
      expect(json['audio_url'], 'https://example.com/ep1.mp3');
    });

    test('copyWith updates listenProgress', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      final updated = ep.copyWith(listenProgress: 120);
      expect(updated.listenProgress, 120);
      expect(updated.guid, ep.guid);
    });

    test('copyWith updates isCompleted', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      final completed = ep.copyWith(isCompleted: true);
      expect(completed.isCompleted, true);
    });

    test('copyWith updates downloadState', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      final downloading = ep.copyWith(downloadState: DownloadState.downloading);
      expect(downloading.downloadState, DownloadState.downloading);
    });

    test('copyWith updates localPath', () {
      final ep = PodcastEpisode.fromJson(sampleJson);
      final downloaded = ep.copyWith(
        downloadState: DownloadState.downloaded,
        localPath: '/storage/audio/ep1.mp3',
      );
      expect(downloaded.localPath, '/storage/audio/ep1.mp3');
    });
  });

  // ── ListeningHistory ────────────────────────────────────────────────────────

  group('ListeningHistory', () {
    test('fromJson parses all fields', () {
      final history = ListeningHistory.fromJson(<String, dynamic>{
        'episode_guid': 'ep-001',
        'feed_url': 'https://example.com/feed.rss',
        'last_position_seconds': 120,
        'total_listened_seconds': 300,
        'completed': false,
        'completed_at': null,
        'updated_at': '2024-01-15T10:00:00.000Z',
      });
      expect(history.episodeGuid, 'ep-001');
      expect(history.feedUrl, 'https://example.com/feed.rss');
      expect(history.lastPositionSeconds, 120);
      expect(history.totalListenedSeconds, 300);
      expect(history.completed, false);
      expect(history.completedAt, isNull);
    });

    test('fromJson parses completed_at date', () {
      final history = ListeningHistory.fromJson(<String, dynamic>{
        'episode_guid': 'ep-001',
        'feed_url': 'https://example.com/feed.rss',
        'completed': true,
        'completed_at': '2024-01-20T08:30:00.000Z',
        'updated_at': '2024-01-20T08:30:00.000Z',
      });
      expect(history.completed, true);
      expect(history.completedAt, isNotNull);
      expect(history.completedAt!.year, 2024);
    });

    test('toJson roundtrip preserves episode_guid', () {
      final history = ListeningHistory.fromJson(<String, dynamic>{
        'episode_guid': 'guid-test',
        'feed_url': 'https://example.com/feed.rss',
        'updated_at': '2024-01-15T10:00:00.000Z',
      });
      final json = history.toJson();
      expect(json['episode_guid'], 'guid-test');
    });

    test('toJson includes updated_at as ISO string', () {
      final history = ListeningHistory.fromJson(<String, dynamic>{
        'episode_guid': 'ep-1',
        'feed_url': 'https://example.com/feed.rss',
        'updated_at': '2024-06-01T12:00:00.000Z',
      });
      final json = history.toJson();
      expect(json['updated_at'], isA<String>());
    });

    test('toJson completed_at is null when not completed', () {
      final history = ListeningHistory.fromJson(<String, dynamic>{
        'episode_guid': 'ep-1',
        'feed_url': 'https://example.com/feed.rss',
        'completed': false,
        'updated_at': '2024-01-01T00:00:00.000Z',
      });
      final json = history.toJson();
      expect(json['completed_at'], isNull);
    });
  });

  // ── UserPodcastFollow ───────────────────────────────────────────────────────

  group('UserPodcastFollow', () {
    test('fromJson parses all fields', () {
      final follow = UserPodcastFollow.fromJson(<String, dynamic>{
        'feed_url': 'https://example.com/feed.rss',
        'podcast_title': 'Learn English Daily',
        'artwork_url': 'https://example.com/art.jpg',
        'followed_at': '2024-02-01T09:00:00.000Z',
      });
      expect(follow.feedUrl, 'https://example.com/feed.rss');
      expect(follow.podcastTitle, 'Learn English Daily');
      expect(follow.artworkUrl, 'https://example.com/art.jpg');
      expect(follow.followedAt.year, 2024);
      expect(follow.followedAt.month, 2);
    });

    test('fromJson defaults artworkUrl to empty string', () {
      final follow = UserPodcastFollow.fromJson(<String, dynamic>{
        'feed_url': 'https://example.com/feed.rss',
        'podcast_title': 'Test',
        'followed_at': '2024-01-01T00:00:00.000Z',
      });
      expect(follow.artworkUrl, '');
    });

    test('toJson roundtrip preserves feed_url', () {
      final follow = UserPodcastFollow.fromJson(<String, dynamic>{
        'feed_url': 'https://example.com/feed.rss',
        'podcast_title': 'Test',
        'followed_at': '2024-01-01T00:00:00.000Z',
      });
      final json = follow.toJson();
      expect(json['feed_url'], 'https://example.com/feed.rss');
      expect(json['podcast_title'], 'Test');
    });

    test('toJson followed_at is ISO string', () {
      final follow = UserPodcastFollow.fromJson(<String, dynamic>{
        'feed_url': 'https://example.com/feed.rss',
        'podcast_title': 'Test',
        'followed_at': '2024-05-10T08:00:00.000Z',
      });
      final json = follow.toJson();
      expect(json['followed_at'], isA<String>());
      expect(json['followed_at'], contains('2024'));
    });
  });

  // ── PodcastCategory ─────────────────────────────────────────────────────────

  group('PodcastCategory', () {
    test('fromJson parses id and label', () {
      final cat = PodcastCategory.fromJson(<String, dynamic>{
        'id': 'A1-A2',
        'label': 'Beginner (A1-A2)',
        'cefr_level': 'A1',
        'podcasts': [],
      });
      expect(cat.id, 'A1-A2');
      expect(cat.label, 'Beginner (A1-A2)');
      expect(cat.cefrLevel, 'A1');
    });

    test('fromJson parses nested podcasts list', () {
      final cat = PodcastCategory.fromJson(<String, dynamic>{
        'id': 'B1-B2',
        'label': 'Intermediate (B1-B2)',
        'cefr_level': 'B1',
        'podcasts': [
          {
            'id': 'pod001',
            'title': 'All Ears English',
            'author': 'Lindsay McMahon',
            'feed_url': 'https://allears.libsyn.com/rss',
            'cefr_level': 'B1',
          },
        ],
      });
      expect(cat.podcasts.length, 1);
      expect(cat.podcasts.first.title, 'All Ears English');
    });

    test('fromJson defaults podcasts to empty list', () {
      final cat = PodcastCategory.fromJson(<String, dynamic>{
        'id': 'A1-A2',
        'label': 'Beginner',
      });
      expect(cat.podcasts, isEmpty);
    });

    test('fromJson defaults cefr_level to B1', () {
      final cat = PodcastCategory.fromJson(<String, dynamic>{
        'id': 'test',
        'label': 'Test',
      });
      expect(cat.cefrLevel, 'B1');
    });

    test('toJson roundtrip preserves id and label', () {
      final cat = PodcastCategory.fromJson(<String, dynamic>{
        'id': 'C1-C2',
        'label': 'Advanced (C1-C2)',
        'cefr_level': 'C1',
        'podcasts': [],
      });
      final json = cat.toJson();
      expect(json['id'], 'C1-C2');
      expect(json['label'], 'Advanced (C1-C2)');
      expect(json['cefr_level'], 'C1');
    });

    test('toJson nested podcasts serialized correctly', () {
      final cat = PodcastCategory.fromJson(<String, dynamic>{
        'id': 'test',
        'label': 'Test',
        'cefr_level': 'B2',
        'podcasts': [
          {
            'id': 'p1',
            'title': 'Podcast A',
            'feed_url': 'https://example.com/feed.rss',
            'cefr_level': 'B2',
          },
        ],
      });
      final json = cat.toJson();
      expect((json['podcasts'] as List).length, 1);
      expect((json['podcasts'] as List).first['id'], 'p1');
    });
  });
}
