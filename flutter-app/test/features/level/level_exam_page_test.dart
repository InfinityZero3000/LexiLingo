import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/presentation/pages/level_exam_page.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_exam_provider.dart';
import 'package:provider/provider.dart';

class _Source extends ProficiencyDataSource {
  _Source(this.eligibility) : super(apiClient: ApiClient(enableLogging: false));

  Map<String, dynamic> eligibility;
  Map<String, String>? submitted;

  @override
  Future<Map<String, dynamic>> getLevelExamEligibility() async => eligibility;

  @override
  Future<Map<String, dynamic>> startLevelExam() async => {
    'attempt_id': 'a1',
    'expires_at': DateTime.now()
        .add(const Duration(minutes: 10))
        .toUtc()
        .toIso8601String(),
    'answers': <String, dynamic>{},
    'sections': [
      {
        'level': 'A2',
        'questions': [
          {
            'id': 'q1',
            'prompt': 'First prompt',
            'options': ['right', 'wrong'],
          },
          {
            'id': 'q2',
            'prompt': 'Second prompt',
            'options': ['right', 'wrong'],
          },
        ],
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> submitLevelExam(
    String id,
    Map<String, String> answers,
  ) async {
    submitted = answers;
    return {
      'passed': false,
      'retry_at': '2026-11-16T10:00:00Z',
      'sections': [
        {'level': 'A2', 'correct': 1, 'total': 2, 'passed': false},
      ],
    };
  }
}

Future<void> _pump(WidgetTester tester, _Source source) async {
  tester.view.physicalSize = const Size(600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => LevelExamProvider(dataSource: source),
      child: const MaterialApp(home: LevelExamPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a learner who is not ready sees why and cannot start', (
    tester,
  ) async {
    await _pump(
      tester,
      _Source({
        'available': false,
        'reason': 'not_ready',
        'target_level': 'A2',
        'progress': 40,
        'blockers': ['Complete 10 more lessons'],
      }),
    );

    expect(find.text('levelExam.gateNotReady'), findsOneWidget);
    expect(find.text('Complete 10 more lessons'), findsOneWidget);
    expect(find.text('levelExam.start'), findsNothing);
  });

  testWidgets('a cooldown is its own message', (tester) async {
    await _pump(
      tester,
      _Source({
        'available': false,
        'reason': 'cooldown',
        'retry_at': '2026-11-16T10:00:00Z',
      }),
    );
    expect(find.text('levelExam.gateCooldown'), findsOneWidget);
  });

  testWidgets('sitting the exam: answer every question, then submit', (
    tester,
  ) async {
    final source = _Source({
      'available': true,
      'reason': 'ready',
      'target_level': 'A2',
    });
    await _pump(tester, source);

    await tester.tap(find.text('levelExam.start'));
    await tester.pumpAndSettle();
    expect(find.text('First prompt'), findsOneWidget);

    await tester.tap(find.text('right'));
    await tester.pump();
    await tester.tap(find.text('levelExam.next'));
    await tester.pumpAndSettle();
    expect(find.text('Second prompt'), findsOneWidget);

    // Submit stays disabled until every question has an answer.
    final submit = find.widgetWithText(FilledButton, 'levelExam.submit');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.text('wrong'));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(source.submitted, {'q1': 'right', 'q2': 'wrong'});
    expect(find.text('levelExam.failedTitle'), findsOneWidget);
    expect(find.text('levelExam.retryAt'), findsOneWidget);
  });
}
