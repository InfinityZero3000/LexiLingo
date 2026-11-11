// An "in progress" attempt has no bands yet, so routing its history tile to
// the result page was a dead end. Tapping it must resume the sitting instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/ielts/data/datasources/ielts_data_source.dart';
import 'package:lexilingo_app/features/ielts/domain/entities/ielts_entities.dart';
import 'package:lexilingo_app/features/ielts/presentation/pages/ielts_result_page.dart';
import 'package:lexilingo_app/features/ielts/presentation/pages/ielts_sitting_page.dart';
import 'package:lexilingo_app/features/ielts/presentation/pages/ielts_tests_page.dart';
import 'package:lexilingo_app/features/ielts/presentation/providers/ielts_provider.dart';

class _StubDataSource extends IeltsDataSource {
  _StubDataSource() : super(apiClient: ApiClient());

  @override
  Future<List<IeltsTestSummary>> listTests({String? testType}) async => const [];

  @override
  Future<List<Map<String, dynamic>>> listAttempts({int limit = 20}) async => [
        {
          'attempt_id': 'attempt-1',
          'test_id': 'test-1',
          'test_title': 'Academic Paper 1',
          'status': 'in_progress',
          'skill_scope': 'full',
          'overall_band': null,
        },
      ];

  @override
  Future<IeltsAttemptState> startAttempt(
    String testId, {
    String skillScope = 'full',
  }) async {
    return const IeltsAttemptState(
      attemptId: 'attempt-1',
      status: 'in_progress',
      skillScope: 'full',
      paper: IeltsPaper(
        sections: [
          IeltsSection(
            skill: IeltsSkill.reading,
            parts: [
              IeltsPart(order: 1, passageTitle: 'Resumed passage'),
            ],
          ),
        ],
      ),
    );
  }
}

void main() {
  setUp(() {
    sl.registerFactory<IeltsProvider>(
      () => IeltsProvider(dataSource: _StubDataSource()),
    );
  });

  tearDown(() => sl.reset());

  testWidgets('tapping an in-progress history tile resumes the sitting, not the result page',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IeltsTestsPage()));
    await tester.pumpAndSettle();

    expect(find.text('In progress — tap to continue'), findsOneWidget);

    await tester.tap(find.text('Academic Paper 1'));
    await tester.pumpAndSettle();

    expect(find.byType(IeltsSittingPage), findsOneWidget);
    expect(find.byType(IeltsResultPage), findsNothing);
    expect(find.text('Resumed passage'), findsOneWidget);
  });
}
