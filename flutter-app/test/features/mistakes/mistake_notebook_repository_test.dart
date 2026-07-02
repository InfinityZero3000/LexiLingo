import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MistakeNotebookRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves entries sorted by review state and recency', () async {
      final repository = MistakeNotebookRepository();
      final older = _entry(id: 'older', createdAt: DateTime(2026));
      final newer = _entry(id: 'newer', createdAt: DateTime(2026, 1, 2));

      await repository.saveMistake(older);
      await repository.saveMistake(newer);

      final entries = await repository.getEntries();

      expect(entries.map((entry) => entry.id), ['newer', 'older']);
    });

    test('upserts repeated mistake and makes it unreviewed again', () async {
      final repository = MistakeNotebookRepository();
      final mistake = _entry(id: 'repeat', createdAt: DateTime(2026));

      await repository.saveMistake(mistake);
      await repository.markReviewed('repeat');
      await repository.saveMistake(
        mistake.copyWith(selectedAnswer: 'C', createdAt: DateTime(2026, 1, 3)),
      );

      final entries = await repository.getEntries();

      expect(entries, hasLength(1));
      expect(entries.single.selectedAnswer, 'C');
      expect(entries.single.isReviewed, isFalse);
      expect(entries.single.reviewCount, 1);
    });

    test('marks entries reviewed and clears reviewed items', () async {
      final repository = MistakeNotebookRepository();

      await repository.saveMistake(_entry(id: 'a'));
      await repository.saveMistake(_entry(id: 'b'));
      await repository.markReviewed('a');

      var entries = await repository.getEntries();
      expect(entries.first.id, 'b');
      expect(entries.last.id, 'a');
      expect(entries.last.reviewCount, 1);

      await repository.clearReviewed();
      entries = await repository.getEntries();

      expect(entries.map((entry) => entry.id), ['b']);
    });

    test('buildId is stable for identical quiz context', () {
      final first = MistakeNotebookEntry.buildId(
        sourceType: 'book_quiz',
        sourceId: 'book-1',
        questionId: 'q1',
        selectedAnswer: 'A',
      );
      final second = MistakeNotebookEntry.buildId(
        sourceType: 'book_quiz',
        sourceId: 'book-1',
        questionId: 'q1',
        selectedAnswer: 'A',
      );

      expect(first, second);
    });
  });
}

MistakeNotebookEntry _entry({required String id, DateTime? createdAt}) {
  return MistakeNotebookEntry(
    id: id,
    sourceType: 'book_quiz',
    sourceId: 'book-1',
    sourceTitle: 'Demo book',
    question: 'What happened?',
    selectedAnswer: 'A',
    correctAnswer: 'B',
    explanation: 'Because the text says so.',
    skill: 'reading',
    createdAt: createdAt ?? DateTime(2026),
  );
}
