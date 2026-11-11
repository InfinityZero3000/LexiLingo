import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
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

    testWidgets('starts the journey at the level held before the first change', (
      tester,
    ) async {
      final provider = ProficiencyProvider(
        dataSource: _Source({
          'history': [
            _row('A2', 'B1', '2026-09-01T00:00:00Z'),
            _row('A1', 'A2', '2026-08-01T00:00:00Z'),
          ],
        }),
      );

      await pump(tester, provider);

      // Nodes read A1 (start) → A2 → B1, and none shows the server's English reason.
      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();
      expect(labels.where((l) => l == 'A1' || l == 'A2' || l == 'B1'), [
        'A1',
        'A2',
        'B1',
      ]);
      expect(find.textContaining('Level updated based on'), findsNothing);
      expect(find.text('profile.levelStart'), findsOneWidget);
      expect(find.text('profile.levelPromoted'), findsNWidgets(2));
    });

    testWidgets('says so when the learner has not changed level yet', (
      tester,
    ) async {
      final provider = ProficiencyProvider(
        dataSource: _Source({'history': []}),
      );

      await pump(tester, provider);

      expect(find.text('profile.levelJourneyEmpty'), findsOneWidget);
      expect(find.text('profile.levelStart'), findsOneWidget);
    });

    testWidgets('offers a retry when loading fails', (tester) async {
      final source = _Source({'history': []}, fail: true);
      final provider = ProficiencyProvider(dataSource: source);

      await pump(tester, provider);
      expect(find.text('profile.levelJourneyFailed'), findsOneWidget);

      source.fail = false;
      await tester.tap(find.text('common.retry'));
      await tester.pumpAndSettle();

      expect(find.text('profile.levelJourneyEmpty'), findsOneWidget);
    });
  });
}
