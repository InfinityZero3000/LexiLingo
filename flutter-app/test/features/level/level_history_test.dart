import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/domain/entities/level_history_entry.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/level/presentation/widgets/level_history_timeline.dart';
import 'package:provider/provider.dart';

class _Source extends ProficiencyDataSource {
  _Source(this.response, {this.fail = false})
    : super(apiClient: ApiClient(enableLogging: false));

  Map<String, dynamic> response;
  bool fail;
  int calls = 0;
  ProficiencyProfile? profile;

  @override
  Future<ProficiencyProfile> getProfile() async =>
      profile ?? ProficiencyProfile.empty();

  @override
  Future<Map<String, dynamic>> getLevelHistory({int limit = 10}) async {
    calls += 1;
    if (fail) throw Exception('offline');
    return response;
  }
}

Map<String, dynamic> _row(
  String from,
  String to,
  String at, {
  String type = 'promotion',
}) => {
  'previous_level': from,
  'new_level': to,
  'change_type': type,
  'reason': 'Level updated based on proficiency assessment',
  'triggered_at': at,
};

void main() {
  group('parseLevelHistory', () {
    test('orders the server\'s newest-first rows oldest first', () {
      final entries = parseLevelHistory({
        'current_level': 'B1',
        'history': [
          _row('A2', 'B1', '2026-09-01T00:00:00Z'),
          _row('A1', 'A2', '2026-08-01T00:00:00Z'),
        ],
      });

      expect(entries.map((e) => e.newLevel), ['A2', 'B1']);
    });

    test(
      'treats a demotion as a demotion and anything else as a promotion',
      () {
        final entries = parseLevelHistory({
          'history': [
            _row('B1', 'A2', '2026-10-01T00:00:00Z', type: 'demotion'),
            _row('A2', 'B1', '2026-09-01T00:00:00Z'),
          ],
        });

        expect(entries.map((e) => e.isPromotion), [true, false]);
      },
    );

    test(
      'skips rows it cannot read instead of dropping the whole timeline',
      () {
        final entries = parseLevelHistory({
          'history': [
            {
              'previous_level': 'A1',
              'new_level': 'A2',
              'triggered_at': 'not a date',
            },
            {'new_level': 'B1', 'triggered_at': '2026-09-01T00:00:00Z'},
            'junk',
            _row('A2', 'B1', '2026-09-01T00:00:00Z'),
          ],
        });

        expect(entries, hasLength(1));
      },
    );

    test(
      'skips a row that records no change and flags the first placement',
      () {
        final entries = parseLevelHistory({
          'history': [
            _row('A1', 'B1', '2026-09-01T00:00:00Z', type: 'initial'),
            _row('A1', 'A1', '2026-08-01T00:00:00Z'),
          ],
        });

        expect(entries, hasLength(1));
        expect(entries.single.isInitial, isTrue);
      },
    );

    test('a self-set reads its direction from the levels and is flagged', () {
      final entries = parseLevelHistory({
        'history': [
          _row('B2', 'A2', '2026-10-01T00:00:00Z', type: 'self_set'),
          _row('A1', 'B2', '2026-09-01T00:00:00Z', type: 'self_set'),
        ],
      });

      expect(entries.map((e) => e.isSelfSet), [true, true]);
      expect(entries.map((e) => e.isPromotion), [true, false]);
    });

    test('an empty or missing history is an empty list', () {
      expect(parseLevelHistory({'history': []}), isEmpty);
      expect(parseLevelHistory({}), isEmpty);
    });
  });

  group('ProficiencyProvider.loadHistory', () {
    test('loads once and only refetches when forced', () async {
      final source = _Source({
        'history': [_row('A1', 'A2', '2026-08-01T00:00:00Z')],
      });
      final provider = ProficiencyProvider(dataSource: source);

      await provider.loadHistory();
      await provider.loadHistory();
      expect(source.calls, 1);
      expect(provider.history.single.newLevel, 'A2');

      await provider.loadHistory(force: true);
      expect(source.calls, 2);
    });

    test('a failure is reported and a later retry can recover', () async {
      final source = _Source({'history': []}, fail: true);
      final provider = ProficiencyProvider(dataSource: source);

      await provider.loadHistory();
      expect(provider.historyFailed, isTrue);
      expect(provider.historyLoaded, isFalse);

      source.fail = false;
      await provider.loadHistory(force: true);
      expect(provider.historyFailed, isFalse);
      expect(provider.historyLoaded, isTrue);
    });
  });

  group('LevelHistoryTimeline', () {
    Future<void> pump(WidgetTester tester, ProficiencyProvider provider) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: LevelHistoryTimeline()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String?> chips(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((l) => const {'A1', 'A2', 'B1', 'B2'}.contains(l))
        .toList();

    testWidgets(
      'shows the path as one row of chips and only the latest change',
      (tester) async {
        final provider = ProficiencyProvider(
          dataSource: _Source({
            'history': [
              _row('A2', 'B1', '2026-09-01T00:00:00Z'),
              _row('A1', 'A2', '2026-08-01T00:00:00Z'),
            ],
          }),
        );

        await pump(tester, provider);

        // A1 (start) → A2 → B1, and none shows the server's English reason.
        expect(chips(tester), ['A1', 'A2', 'B1']);
        expect(find.textContaining('Level updated based on'), findsNothing);
        expect(find.textContaining('profile.levelPromoted'), findsOneWidget);
        expect(find.text('profile.levelStart'), findsNothing);
        expect(find.text('profile.levelTestRule'), findsOneWidget);
      },
    );

    testWidgets('a demotion in old data is marked, not hidden', (tester) async {
      final provider = ProficiencyProvider(
        dataSource: _Source({
          'history': [
            _row('B1', 'A2', '2026-09-01T00:00:00Z', type: 'demotion'),
            _row('A2', 'B1', '2026-08-01T00:00:00Z'),
          ],
        }),
      );

      await pump(tester, provider);

      expect(chips(tester), ['A2', 'B1', 'A2']);
      expect(find.textContaining('profile.levelDemoted'), findsOneWidget);
    });

    testWidgets('a self-chosen level reads as chosen, not as moved up', (
      tester,
    ) async {
      final provider = ProficiencyProvider(
        dataSource: _Source({
          'history': [
            _row('B1', 'A2', '2026-09-01T00:00:00Z', type: 'self_set'),
          ],
        }),
      );

      await pump(tester, provider);

      expect(find.textContaining('profile.levelSelfSet'), findsOneWidget);
      expect(find.textContaining('profile.levelPromoted'), findsNothing);
      expect(find.textContaining('profile.levelDemoted'), findsNothing);
    });

    testWidgets('a long path keeps the newest steps and an ellipsis', (
      tester,
    ) async {
      final levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'A1', 'A2'];
      final provider = ProficiencyProvider(
        dataSource: _Source({
          'history': [
            for (var i = levels.length - 1; i > 0; i--)
              _row(levels[i - 1], levels[i], '2026-0${i + 1}-01T00:00:00Z'),
          ],
        }),
      );

      await pump(tester, provider);

      expect(find.text('…'), findsOneWidget);
      expect(find.byType(Wrap), findsOneWidget);
    });

    testWidgets(
      'says the path starts here when the learner has not changed level',
      (tester) async {
        final provider = ProficiencyProvider(
          dataSource: _Source({'history': []}),
        );

        await pump(tester, provider);

        expect(find.text('profile.levelStart'), findsOneWidget);
        expect(find.text('profile.levelTestRule'), findsOneWidget);
      },
    );

    testWidgets('offers the level test once the requirements are met', (
      tester,
    ) async {
      final source = _Source({'history': []})
        ..profile = ProficiencyProfile.fromJson({
          'assessed_level': 'A1',
          'next_level': {
            'level': 'A2',
            'progress': 100.0,
            'qualifies': true,
            'requirements': <String, dynamic>{},
            'blockers': <String>[],
          },
        });
      final provider = ProficiencyProvider(dataSource: source);
      await provider.loadProfile();
      expect(provider.nextLevel?.qualifies, isTrue);

      await pump(tester, provider);

      expect(find.text('profile.levelTestReady'), findsOneWidget);
      expect(find.text('profile.levelTestTake'), findsOneWidget);
      expect(find.text('profile.levelTestRule'), findsNothing);
    });

    testWidgets('offers a retry when loading fails', (tester) async {
      final source = _Source({'history': []}, fail: true);
      final provider = ProficiencyProvider(dataSource: source);

      await pump(tester, provider);
      expect(find.text('profile.levelJourneyFailed'), findsOneWidget);

      source.fail = false;
      await tester.tap(find.text('common.retry'));
      await tester.pumpAndSettle();

      expect(find.text('profile.levelStart'), findsOneWidget);
    });
  });
}
