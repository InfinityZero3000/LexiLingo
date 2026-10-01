import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/data/models/content_activity_model.dart';
import 'package:lexilingo_app/features/progress/domain/entities/content_activity_entity.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/content_activity_provider.dart';

import 'content_activity_test_doubles.dart';

/// The Content tab of Progress.
///
/// It exists so a learner can see that time on the library, podcast, video and
/// news surfaces was actually credited — those four earned XP for months while
/// counting toward nothing.
void main() {
  group('ContentActivityModel', () {
    test('parses the endpoint payload', () {
      final model = ContentActivityModel.fromJson({
        'days': 7,
        'total_minutes': 35,
        'total_sessions': 3,
        'total_xp': 30,
        'by_source': [
          {
            'source': 'youtube',
            'sessions': 2,
            'minutes': 15,
            'tracks_minutes': true,
            'xp_earned': 10,
            'last_active_at': '2026-10-01T10:00:00+00:00',
          },
          {
            'source': 'news',
            'sessions': 1,
            'minutes': 0,
            'tracks_minutes': false,
            'xp_earned': 20,
            'last_active_at': null,
          },
        ],
      });

      expect(model.totalMinutes, 35);
      expect(model.bySource, hasLength(2));
      expect(model.bySource.first.tracksMinutes, isTrue);
      expect(model.bySource.first.lastActiveAt?.year, 2026);
      expect(model.bySource.last.lastActiveAt, isNull);
    });

    test('survives a payload with fields missing', () {
      final model = ContentActivityModel.fromJson({});
      expect(model.days, 7);
      expect(model.bySource, isEmpty);
      expect(model.isEmpty, isTrue);
    });

    test('hasActivity is driven by sessions, not minutes', () {
      // news and books report 0 minutes by design; they are still activity.
      final news = ContentSourceActivityModel.fromJson({
        'source': 'news',
        'sessions': 2,
        'minutes': 0,
        'tracks_minutes': false,
      });
      expect(news.hasActivity, isTrue);
    });
  });

  group('ContentActivityProvider', () {
    test('exposes timed and counted sources separately', () async {
      final provider = ContentActivityProvider(
        repository: FakeProgressRepository(
          activity: _activity(
            const [
              ContentSourceActivityEntity(
                source: 'youtube',
                sessions: 1,
                minutes: 10,
                tracksMinutes: true,
                xpEarned: 5,
              ),
              ContentSourceActivityEntity(
                source: 'book',
                sessions: 2,
                minutes: 0,
                tracksMinutes: false,
                xpEarned: 40,
              ),
            ],
          ),
        ),
      );

      await provider.load();

      expect(provider.timedSources.map((s) => s.source), ['youtube']);
      expect(provider.countedSources.map((s) => s.source), ['book']);
    });

    test('surfaces a failure message and keeps the empty state', () async {
      final provider = ContentActivityProvider(
        repository: FakeProgressRepository(
          failure: const ServerFailure('backend down'),
        ),
      );

      await provider.load();

      expect(provider.errorMessage, 'backend down');
      expect(provider.activity.isEmpty, isTrue);
      expect(provider.isLoading, isFalse);
    });

    test('does not refetch the same window twice', () async {
      final repository = FakeProgressRepository(
        activity: _activity(const [
          ContentSourceActivityEntity(
            source: 'youtube',
            sessions: 1,
            minutes: 10,
            tracksMinutes: true,
            xpEarned: 5,
          ),
        ]),
      );
      final provider = ContentActivityProvider(repository: repository);

      await provider.load();
      await provider.load();

      expect(repository.calls, 1);
    });

    test('refetches when forced, and when the window changes', () async {
      final repository = FakeProgressRepository(
        activity: _activity(const [
          ContentSourceActivityEntity(
            source: 'youtube',
            sessions: 1,
            minutes: 10,
            tracksMinutes: true,
            xpEarned: 5,
          ),
        ]),
      );
      final provider = ContentActivityProvider(repository: repository);

      await provider.load();
      await provider.load(force: true);
      await provider.load(days: 30);

      expect(repository.calls, 3);
      expect(repository.lastDays, 30);
      expect(provider.days, 30);
    });
  });
}

ContentActivityEntity _activity(List<ContentSourceActivityEntity> sources) =>
    ContentActivityEntity(
      days: 7,
      totalMinutes: sources.fold(0, (sum, s) => sum + s.minutes),
      totalSessions: sources.fold(0, (sum, s) => sum + s.sessions),
      totalXp: sources.fold(0, (sum, s) => sum + s.xpEarned),
      bySource: sources,
    );
