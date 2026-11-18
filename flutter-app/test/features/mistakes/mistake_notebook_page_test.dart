import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';
import 'package:lexilingo_app/features/mistakes/presentation/pages/mistake_notebook_page.dart';

class _FakeRepository extends MistakeNotebookRepository {
  _FakeRepository();

  bool failLoad = false;
  bool failMutation = false;
  int loads = 0;
  final List<MistakeNotebookEntry> entries = [_entry];

  @override
  Future<List<MistakeNotebookEntry>> getEntries() async {
    loads++;
    if (failLoad) throw StateError('storage unavailable');
    return List.of(entries);
  }

  @override
  Future<void> markReviewed(String id) async {
    if (failMutation) throw StateError('write failed');
    entries[0] = _entry.copyWith(reviewedAt: DateTime(2026), reviewCount: 1);
  }
}

final _entry = MistakeNotebookEntry(
  id: 'm1',
  sourceType: 'book_quiz',
  sourceId: 'b1',
  sourceTitle: 'Book',
  question: 'Pick one',
  selectedAnswer: 'a',
  correctAnswer: 'b',
  explanation: '',
  skill: 'reading',
  createdAt: DateTime(2026),
);

Widget _host(_FakeRepository repository) =>
    MaterialApp(home: MistakeNotebookPage(repository: repository));

void main() {
  testWidgets(
    'a failed first load shows an error with retry, not an empty book',
    (tester) async {
      final repository = _FakeRepository()..failLoad = true;

      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      expect(find.text('mistakeNotebook.emptyTitle'), findsNothing);
      expect(find.text('common.retry'), findsOneWidget);

      repository.failLoad = false;
      await tester.tap(find.text('common.retry'));
      await tester.pumpAndSettle();

      expect(find.text('Pick one'), findsOneWidget);
    },
  );

  testWidgets('a failed refresh keeps the entries already on screen', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();

    repository.failLoad = true;
    await tester.tap(find.byTooltip('common.refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Pick one'), findsOneWidget);
  });

  testWidgets('marking reviewed reloads in place and survives a failed write', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeRepository();
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();

    repository.failMutation = true;
    await tester.tap(find.text('mistakeNotebook.markReviewed'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('mistakeNotebook.markReviewed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    repository.failMutation = false;
    await tester.tap(find.text('mistakeNotebook.markReviewed'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('mistakeNotebook.reopen'), findsOneWidget);
  });
}
