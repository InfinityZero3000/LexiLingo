import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/chat/presentation/helpers/chat_mistake_recorder.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ChatMistakeRecorder', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves a chat correction as a mistake notebook entry', () async {
      final repository = MistakeNotebookRepository();
      final recorder = ChatMistakeRecorder(
        repository: repository,
        now: () => DateTime(2026, 8, 10),
      );

      final saved = await recorder.recordGrammarCorrection(
        sourceType: 'topic_chat',
        sourceId: 'session-1',
        original: 'I go there yesterday',
        corrected: 'I went there yesterday',
        explanation: 'Use past tense for completed past actions.',
        errorType: 'verb_tense',
      );

      final entries = await repository.getEntries();

      expect(saved, isTrue);
      expect(entries, hasLength(1));
      expect(entries.single.sourceType, 'topic_chat');
      expect(entries.single.sourceTitle, 'Topic Chat');
      expect(entries.single.selectedAnswer, 'I go there yesterday');
      expect(entries.single.correctAnswer, 'I went there yesterday');
      expect(entries.single.skill, 'grammar');
      expect(entries.single.createdAt, DateTime(2026, 8, 10));
    });

    test('never stores the error label as the skill', () async {
      final repository = MistakeNotebookRepository();
      final recorder = ChatMistakeRecorder(repository: repository);

      await recorder.recordGrammarCorrection(
        sourceType: 'topic_chat',
        sourceId: 's',
        original: 'I go',
        corrected: 'I went',
        explanation: '',
        errorType: 'article_error',
      );

      expect((await repository.getEntries()).single.skill, 'grammar');
    });

    test('spelling and word choice go to the vocabulary skill', () async {
      for (final type in ['spelling', 'word_choice']) {
        SharedPreferences.setMockInitialValues({});
        final repository = MistakeNotebookRepository();
        await ChatMistakeRecorder(
          repository: repository,
        ).recordGrammarCorrection(
          sourceType: 'topic_chat',
          sourceId: 's',
          original: 'recieve',
          corrected: 'receive',
          explanation: '',
          errorType: type,
        );

        expect((await repository.getEntries()).single.skill, 'vocabulary');
      }
    });

    test(
      'returns false and saves nothing when there is no correction',
      () async {
        final repository = MistakeNotebookRepository();
        final recorder = ChatMistakeRecorder(repository: repository);

        final saved = await recorder.recordGrammarCorrection(
          sourceType: 'lexi_chat',
          sourceId: 'msg-1',
          original: 'something',
          corrected: '   ',
          explanation: '',
        );

        expect(saved, isFalse);
        expect(await repository.getEntries(), isEmpty);
      },
    );

    test('defaults skill to grammar when no error type is given', () async {
      final repository = MistakeNotebookRepository();
      final recorder = ChatMistakeRecorder(repository: repository);

      await recorder.recordGrammarCorrection(
        sourceType: 'lexi_chat',
        sourceId: 'msg-2',
        original: 'go',
        corrected: 'went',
        explanation: 'past tense',
      );

      expect((await repository.getEntries()).single.skill, 'grammar');
    });
  });
}
