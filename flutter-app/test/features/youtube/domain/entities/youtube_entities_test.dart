import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/youtube/domain/entities/youtube_entities.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // YouTubeVideo
  // ─────────────────────────────────────────────────────────────────────────
  group('YouTubeVideo', () {
    group('fromJson', () {
      test('parses all fields correctly', () {
        final json = {
          'video_id': 'dQw4w9WgXcQ',
          'title': 'Learn English Grammar',
          'description': 'A comprehensive grammar lesson',
          'channel_title': 'BBC Learning English',
          'channel_id': 'UCHaHD477h-FeBbrgBrwTDpA',
          'published_at': '2024-01-15T10:00:00Z',
          'thumbnail_url': 'https://example.com/high.jpg',
          'thumbnail_medium': 'https://example.com/medium.jpg',
        };

        final video = YouTubeVideo.fromJson(json);

        expect(video.videoId, 'dQw4w9WgXcQ');
        expect(video.title, 'Learn English Grammar');
        expect(video.description, 'A comprehensive grammar lesson');
        expect(video.channelTitle, 'BBC Learning English');
        expect(video.channelId, 'UCHaHD477h-FeBbrgBrwTDpA');
        expect(video.publishedAt, '2024-01-15T10:00:00Z');
        expect(video.thumbnailUrl, 'https://example.com/high.jpg');
        expect(video.thumbnailMedium, 'https://example.com/medium.jpg');
      });

      test('uses empty string defaults for missing fields', () {
        final video = YouTubeVideo.fromJson({});

        expect(video.videoId, '');
        expect(video.title, '');
        expect(video.description, '');
        expect(video.channelTitle, '');
        expect(video.channelId, '');
        expect(video.publishedAt, '');
        expect(video.thumbnailUrl, '');
        expect(video.thumbnailMedium, '');
      });

      test('handles null values with empty string fallback', () {
        final json = {
          'video_id': null,
          'title': null,
          'description': null,
          'channel_title': null,
          'channel_id': null,
          'published_at': null,
          'thumbnail_url': null,
          'thumbnail_medium': null,
        };

        final video = YouTubeVideo.fromJson(json);

        expect(video.videoId, '');
        expect(video.title, '');
        expect(video.thumbnailMedium, '');
      });

      test('thumbnailMedium defaults to empty string when not provided', () {
        final json = {
          'video_id': 'abc',
          'title': 'Test',
          'description': '',
          'channel_title': 'Channel',
          'channel_id': 'ch1',
          'published_at': '2024-01-01',
          'thumbnail_url': 'https://thumb.jpg',
          // thumbnail_medium omitted
        };

        final video = YouTubeVideo.fromJson(json);
        expect(video.thumbnailMedium, '');
      });
    });

    group('toJson', () {
      test('serializes all fields to correct keys', () {
        const video = YouTubeVideo(
          videoId: 'vid123',
          title: 'English Lesson',
          description: 'Learn English today',
          channelTitle: 'TED-Ed',
          channelId: 'UCsooa4yRKGN_zEE8iknghZA',
          publishedAt: '2024-03-01T00:00:00Z',
          thumbnailUrl: 'https://thumb-high.jpg',
          thumbnailMedium: 'https://thumb-medium.jpg',
        );

        final json = video.toJson();

        expect(json['video_id'], 'vid123');
        expect(json['title'], 'English Lesson');
        expect(json['description'], 'Learn English today');
        expect(json['channel_title'], 'TED-Ed');
        expect(json['channel_id'], 'UCsooa4yRKGN_zEE8iknghZA');
        expect(json['published_at'], '2024-03-01T00:00:00Z');
        expect(json['thumbnail_url'], 'https://thumb-high.jpg');
        expect(json['thumbnail_medium'], 'https://thumb-medium.jpg');
      });

      test('roundtrip fromJson → toJson preserves data', () {
        final originalJson = {
          'video_id': 'roundtrip_id',
          'title': 'Roundtrip Test',
          'description': 'Test description',
          'channel_title': 'Test Channel',
          'channel_id': 'ch_test',
          'published_at': '2024-06-01T00:00:00Z',
          'thumbnail_url': 'https://img.jpg',
          'thumbnail_medium': 'https://img_m.jpg',
        };

        final video = YouTubeVideo.fromJson(originalJson);
        final resultJson = video.toJson();

        expect(resultJson['video_id'], originalJson['video_id']);
        expect(resultJson['title'], originalJson['title']);
        expect(
          resultJson['thumbnail_medium'],
          originalJson['thumbnail_medium'],
        );
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // YouTubeChannel
  // ─────────────────────────────────────────────────────────────────────────
  group('YouTubeChannel', () {
    test('parses all fields from JSON', () {
      final json = {
        'id': 'UCHaHD477h-FeBbrgBrwTDpA',
        'name': 'BBC Learning English',
        'description': 'Learn English with BBC',
        'level': 'A2-B2',
        'thumbnail': 'https://yt3.googleusercontent.com/BBC',
        'category': 'general',
      };

      final channel = YouTubeChannel.fromJson(json);

      expect(channel.id, 'UCHaHD477h-FeBbrgBrwTDpA');
      expect(channel.name, 'BBC Learning English');
      expect(channel.description, 'Learn English with BBC');
      expect(channel.level, 'A2-B2');
      expect(channel.thumbnail, 'https://yt3.googleusercontent.com/BBC');
      expect(channel.category, 'general');
    });

    test('handles missing fields with empty string defaults', () {
      final channel = YouTubeChannel.fromJson({});

      expect(channel.id, '');
      expect(channel.name, '');
      expect(channel.category, '');
    });

    test('handles null values with fallback to empty string', () {
      final json = {
        'id': null,
        'name': null,
        'description': null,
        'level': null,
        'thumbnail': null,
        'category': null,
      };

      final channel = YouTubeChannel.fromJson(json);

      expect(channel.id, '');
      expect(channel.name, '');
      expect(channel.level, '');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CaptionSegment
  // ─────────────────────────────────────────────────────────────────────────
  group('CaptionSegment', () {
    test('parses start_ms, end_ms, text from JSON', () {
      final json = {
        'start_ms': 1000,
        'end_ms': 3500,
        'text': 'Hello, welcome to this lesson',
      };

      final segment = CaptionSegment.fromJson(json);

      expect(segment.startMs, 1000);
      expect(segment.endMs, 3500);
      expect(segment.text, 'Hello, welcome to this lesson');
    });

    test('defaults to 0 and empty string for missing fields', () {
      final segment = CaptionSegment.fromJson({});

      expect(segment.startMs, 0);
      expect(segment.endMs, 0);
      expect(segment.text, '');
    });

    group('durationSeconds', () {
      test('calculates duration in seconds correctly', () {
        const segment = CaptionSegment(
          startMs: 1000,
          endMs: 4000,
          text: 'Test',
        );
        expect(segment.durationSeconds, closeTo(3.0, 0.001));
      });

      test('zero duration when start equals end', () {
        const segment = CaptionSegment(
          startMs: 5000,
          endMs: 5000,
          text: 'Test',
        );
        expect(segment.durationSeconds, 0.0);
      });

      test('duration is fractional for sub-second segments', () {
        const segment = CaptionSegment(startMs: 0, endMs: 500, text: 'Short');
        expect(segment.durationSeconds, closeTo(0.5, 0.001));
      });
    });

    group('isActiveAt', () {
      const segment = CaptionSegment(
        startMs: 2000,
        endMs: 5000,
        text: 'Active segment',
      );

      test('active at start position', () {
        expect(segment.isActiveAt(2000), isTrue);
      });

      test('active during middle of segment', () {
        expect(segment.isActiveAt(3500), isTrue);
      });

      test('inactive before start', () {
        expect(segment.isActiveAt(1999), isFalse);
      });

      test('inactive at end position (exclusive)', () {
        expect(segment.isActiveAt(5000), isFalse);
      });

      test('inactive after end', () {
        expect(segment.isActiveAt(5001), isFalse);
      });

      test('inactive at position 0 when segment starts later', () {
        expect(segment.isActiveAt(0), isFalse);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // YouTubeSearchResult
  // ─────────────────────────────────────────────────────────────────────────
  group('YouTubeSearchResult', () {
    test('parses nested data field from backend response', () {
      final json = {
        'data': {
          'videos': [
            {
              'video_id': 'v1',
              'title': 'English 101',
              'description': '',
              'channel_title': 'Channel',
              'channel_id': 'ch1',
              'published_at': '2024-01-01',
              'thumbnail_url': '',
              'thumbnail_medium': '',
            },
          ],
          'next_page_token': 'nextToken123',
          'prev_page_token': null,
          'total_results': 100,
        },
        'source': 'redis',
        'is_stale': false,
      };

      final result = YouTubeSearchResult.fromJson(json);

      expect(result.videos.length, 1);
      expect(result.videos[0].videoId, 'v1');
      expect(result.videos[0].title, 'English 101');
      expect(result.nextPageToken, 'nextToken123');
      expect(result.prevPageToken, isNull);
      expect(result.totalResults, 100);
    });

    test('parses direct format without data wrapper', () {
      final json = {
        'videos': [
          {
            'video_id': 'direct_v1',
            'title': 'Direct Format',
            'description': '',
            'channel_title': 'C',
            'channel_id': 'c1',
            'published_at': '',
            'thumbnail_url': '',
          },
        ],
        'next_page_token': null,
        'prev_page_token': null,
        'total_results': 1,
      };

      final result = YouTubeSearchResult.fromJson(json);

      expect(result.videos.length, 1);
      expect(result.videos[0].videoId, 'direct_v1');
      expect(result.totalResults, 1);
    });

    test('handles empty videos list', () {
      final json = {
        'data': {
          'videos': [],
          'next_page_token': null,
          'prev_page_token': null,
          'total_results': 0,
        },
      };

      final result = YouTubeSearchResult.fromJson(json);

      expect(result.videos, isEmpty);
      expect(result.totalResults, 0);
      expect(result.nextPageToken, isNull);
    });

    test('handles missing videos field', () {
      final result = YouTubeSearchResult.fromJson(<String, dynamic>{
        'data': <String, dynamic>{},
      });
      expect(result.videos, isEmpty);
      expect(result.totalResults, 0);
    });

    test('parses multiple videos correctly', () {
      final videoList = List.generate(
        5,
        (i) => {
          'video_id': 'vid$i',
          'title': 'Video $i',
          'description': '',
          'channel_title': 'Test',
          'channel_id': 'ch1',
          'published_at': '2024-01-0${i + 1}',
          'thumbnail_url': '',
        },
      );

      final json = {
        'data': {'videos': videoList, 'total_results': 5},
      };

      final result = YouTubeSearchResult.fromJson(json);
      expect(result.videos.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(result.videos[i].videoId, 'vid$i');
      }
    });
  });
}
