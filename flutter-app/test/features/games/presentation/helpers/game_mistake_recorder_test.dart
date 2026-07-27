import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/helpers/game_mistake_recorder.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('GameMistakeRecorder', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('records fill blank misses as grammar notebook entries', () async {
      final repository = MistakeNotebookRepository();
      final recorder = GameMistakeRecorder(
        repository: repository,
        now: () => DateTime(2026, 7, 2),
      );

      await recorder.recordFillBlankMiss(
        question: const FillBlankQuestion(
          id: 'fb-1',
          sentence: 'She ___ to school every day.',
          options: ['go', 'goes', 'went', 'gone'],
          correctAnswer: 'goes',
          grammarTip: 'Use third-person singular in present simple.',
        ),
        sessionId: 'fill-session',
        questionIndex: 0,
        selectedAnswer: 'go',
      );

      final entries = await repository.getEntries();

      expect(entries, hasLength(1));
      expect(entries.single.sourceType, 'game_fill_blank');
      expect(entries.single.sourceTitle, 'Fill in the Blank');
      expect(entries.single.question, 'She ___ to school every day.');
      expect(entries.single.selectedAnswer, 'go');
      expect(entries.single.correctAnswer, 'goes');
      expect(
        entries.single.explanation,
        'Use third-person singular in present simple.',
      );
      expect(entries.single.skill, 'grammar');
      expect(entries.single.createdAt, DateTime(2026, 7, 2));
    });

    test('records grammar quiz misses with topic metadata', () async {
      final repository = MistakeNotebookRepository();
      final recorder = GameMistakeRecorder(repository: repository);

      await recorder.recordGrammarQuizMiss(
        question: const GrammarQuizQuestion(
          id: 'gq-1',
          question: 'Choose the correct modal verb.',
          options: ['must', 'might', 'can', 'should'],
          correctAnswer: 'should',
          explanation: 'Should is used for advice.',
          topic: 'modal_verbs',
        ),
        sessionId: 'grammar-session',
        questionIndex: 0,
        selectedAnswer: 'must',
      );

      final entries = await repository.getEntries();

      expect(entries.single.sourceType, 'game_grammar_quiz');
      expect(entries.single.sourceTitle, 'Grammar Quiz - Modal Verbs');
      expect(entries.single.skill, 'modal_verbs');
      expect(entries.single.explanation, 'Should is used for advice.');
    });

    test(
      'does not record correct answers and upserts repeated misses',
      () async {
        final repository = MistakeNotebookRepository();
        final recorder = GameMistakeRecorder(repository: repository);
        const question = FillBlankQuestion(
          id: 'fb-2',
          sentence: 'They ___ dinner now.',
          options: ['eat', 'ate', 'are eating', 'eats'],
          correctAnswer: 'are eating',
        );

        await recorder.recordFillBlankMiss(
          question: question,
          sessionId: 'session',
          questionIndex: 0,
          selectedAnswer: 'are eating',
        );
        expect(await repository.getEntries(), isEmpty);

        await recorder.recordFillBlankMiss(
          question: question,
          sessionId: 'session',
          questionIndex: 0,
          selectedAnswer: 'eat',
        );
        await repository.markReviewed(
          (await repository.getEntries()).single.id,
        );
        await recorder.recordFillBlankMiss(
          question: question,
          sessionId: 'session',
          questionIndex: 0,
          selectedAnswer: 'eat',
        );

        final entries = await repository.getEntries();

        expect(entries, hasLength(1));
        expect(entries.single.isReviewed, isFalse);
        expect(entries.single.reviewCount, 1);
      },
    );
  });
}
