import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/ielts/data/datasources/ielts_data_source.dart';
import 'package:lexilingo_app/features/ielts/domain/entities/ielts_entities.dart';
import 'package:lexilingo_app/features/ielts/presentation/pages/ielts_sitting_page.dart';
import 'package:lexilingo_app/features/ielts/presentation/providers/ielts_provider.dart';

class _Source extends IeltsDataSource {
  _Source() : super(apiClient: ApiClient());

  @override
  Future<IeltsAttemptState> startAttempt(
    String testId, {
    String skillScope = 'full',
  }) async {
    return IeltsAttemptState(
      attemptId: 'a1',
      status: 'in_progress',
      skillScope: 'reading',
      paper: IeltsPaper(
        sections: [
          IeltsSection(
            skill: IeltsSkill.reading,
            parts: [
              IeltsPart(
                order: 1,
                passageTitle: 'Bees',
                passageText: List.filled(60, 'Bees make honey.').join(' '),
                groups: const [
                  IeltsQuestionGroup(
                    questionType: 'true_false_notgiven',
                    questions: [
                      IeltsQuestion(key: 'q1', number: 1, prompt: 'Bees fly.'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _test = IeltsTestSummary(
  id: 't1',
  title: 'Reading',
  testType: 'academic',
  skillScope: 'reading',
);

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: IeltsSittingPage(test: _test)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final source = _Source();
    sl.registerFactory<IeltsProvider>(() => IeltsProvider(dataSource: source));
  });
  tearDown(() => sl.reset());

  testWidgets('narrow: a sticky control jumps to the questions', (tester) async {
    await _pump(tester, const Size(375, 700));

    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(find.text('1. Bees fly.').hitTestable(), findsNothing);

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    expect(find.text('1. Bees fly.').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide: passage and questions sit side by side', (tester) async {
    await _pump(tester, const Size(1024, 700));

    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.text('Bees'), findsOneWidget);
    expect(find.text('1. Bees fly.').hitTestable(), findsOneWidget);
    expect(find.byType(ListView), findsNWidgets(2));
  });
}
