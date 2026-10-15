// The Speaking transcript field once carried a key derived from the answer's
// hashCode, so every keystroke rebuilt it from scratch and focus jumped out of
// the field after one character.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/ielts/data/datasources/ielts_data_source.dart';
import 'package:lexilingo_app/features/ielts/domain/entities/ielts_entities.dart';
import 'package:lexilingo_app/features/ielts/presentation/pages/ielts_sitting_page.dart';
import 'package:lexilingo_app/features/ielts/presentation/providers/ielts_provider.dart';

class _StubDataSource extends IeltsDataSource {
  _StubDataSource() : super(apiClient: ApiClient());

  final List<Map<String, dynamic>> saved = [];

  @override
  Future<IeltsAttemptState> startAttempt(
    String testId, {
    String skillScope = 'full',
  }) async {
    return const IeltsAttemptState(
      attemptId: 'attempt-1',
      status: 'in_progress',
      skillScope: 'speaking',
      paper: IeltsPaper(
        sections: [
          IeltsSection(
            skill: IeltsSkill.speaking,
            parts: [
              IeltsPart(
                order: 1,
                partKey: 'speaking_part_1',
                prompt: 'Where do you live?',
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Future<void> saveAnswers(
    String attemptId,
    Map<String, dynamic> answers, {
    int timeSpentSeconds = 0,
  }) async {
    saved.add(answers);
  }
}

const _test = IeltsTestSummary(
  id: 'test-1',
  title: 'Speaking practice',
  testType: 'academic',
  skillScope: 'speaking',
);

void main() {
  setUp(() {
    final dataSource = _StubDataSource();
    sl.registerFactory<IeltsProvider>(
      () => IeltsProvider(dataSource: dataSource),
    );
  });

  tearDown(() => sl.reset());

  testWidgets('typing in the transcript keeps focus and keeps every character',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: IeltsSittingPage(test: _test)),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField);
    expect(field, findsOneWidget);

    await tester.tap(field);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;

    // One character at a time — a rebuild between them is what used to steal
    // the focus and drop what came after it.
    for (final chunk in ['I ', 'I l', 'I li', 'I liv', 'I live']) {
      await tester.enterText(field, chunk);
      await tester.pump();
    }

    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(find.text('I live'), findsOneWidget);
  });
}
