// Opening a test used to create (or resume) a sitting immediately. The learner
// now sees what the test contains first and starts it on purpose.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/ielts/data/datasources/ielts_data_source.dart';
import 'package:lexilingo_app/features/ielts/domain/entities/ielts_entities.dart';
import 'package:lexilingo_app/features/ielts/presentation/providers/ielts_provider.dart';
import 'package:lexilingo_app/features/ielts/presentation/widgets/ielts_preview_sheet.dart';

class _Source extends IeltsDataSource {
  _Source({this.history = const []})
    : super(apiClient: ApiClient(enableLogging: false));

  final List<Map<String, dynamic>> history;
  final List<String> previewed = [];

  @override
  Future<IeltsPaper> getTestPaper(String testId) async {
    previewed.add(testId);
    return const IeltsPaper(
      sections: [
        IeltsSection(
          skill: IeltsSkill.listening,
          durationMinutes: 30,
          parts: [IeltsPart(), IeltsPart()],
        ),
        IeltsSection(
          skill: IeltsSkill.writing,
          durationMinutes: 60,
          parts: [IeltsPart()],
        ),
      ],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listAttempts({int limit = 20}) async =>
      history;
}

const _test = IeltsTestSummary(
  id: 't1',
  title: 'Academic 1',
  testType: 'academic',
  skillScope: 'full',
);

void main() {
  group('IeltsProvider', () {
    test('previewPaper reads the paper without creating an attempt', () async {
      final source = _Source();
      final provider = IeltsProvider(dataSource: source);

      final paper = await provider.previewPaper('t1');

      expect(source.previewed, ['t1']);
      expect(paper.sections.map((s) => s.skill), [
        IeltsSkill.listening,
        IeltsSkill.writing,
      ]);
      expect(provider.attempt, isNull);
    });

    test('knows which tests already have an unfinished sitting', () async {
      final provider = IeltsProvider(
        dataSource: _Source(
          history: [
            {'test_id': 't1', 'status': 'in_progress'},
            {'test_id': 't2', 'status': 'graded'},
          ],
        ),
      );
      await provider.loadHistory();

      expect(provider.hasSittingInProgress('t1'), isTrue);
      expect(provider.hasSittingInProgress('t2'), isFalse);
      expect(provider.hasSittingInProgress('unknown'), isFalse);
    });
  });

  group('IeltsPreviewSheet', () {
    Future<bool?> open(
      WidgetTester tester, {
      required Future<IeltsPaper> Function() loadPaper,
      bool inProgress = false,
    }) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<bool>(
                    context: context,
                    builder: (_) => IeltsPreviewSheet(
                      test: _test,
                      loadPaper: loadPaper,
                      hasSittingInProgress: inProgress,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('lists each section with its parts, questions and time', (
      tester,
    ) async {
      await open(tester, loadPaper: () => _Source().getTestPaper('t1'));

      expect(find.text('Academic 1'), findsOneWidget);
      expect(find.text('ielts.skillListening'), findsOneWidget);
      expect(find.text('ielts.skillWriting'), findsOneWidget);
      expect(find.text('ielts.previewStart'), findsOneWidget);
      expect(find.text('ielts.previewInProgress'), findsNothing);
    });

    testWidgets(
      'offers to continue an unfinished sitting instead of starting one',
      (tester) async {
        await open(
          tester,
          loadPaper: () => _Source().getTestPaper('t1'),
          inProgress: true,
        );

        expect(find.text('ielts.previewInProgress'), findsOneWidget);
        expect(find.text('ielts.previewContinue'), findsOneWidget);
        expect(find.text('ielts.previewStart'), findsNothing);
      },
    );

    testWidgets(
      'still lets the learner start when the contents cannot be loaded',
      (tester) async {
        await open(tester, loadPaper: () async => throw Exception('offline'));

        expect(find.text('ielts.previewFailed'), findsOneWidget);
        expect(find.text('ielts.previewStart'), findsOneWidget);
      },
    );

    testWidgets('starting pops true; dismissing starts nothing', (
      tester,
    ) async {
      bool? started;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    started = await showModalBottomSheet<bool>(
                      context: context,
                      builder: (_) => IeltsPreviewSheet(
                        test: _test,
                        loadPaper: () => _Source().getTestPaper('t1'),
                        hasSittingInProgress: false,
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ielts.previewStart'));
      await tester.pumpAndSettle();

      expect(started, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5)); // the scrim
      await tester.pumpAndSettle();

      expect(started, isNull);
    });
  });
}
