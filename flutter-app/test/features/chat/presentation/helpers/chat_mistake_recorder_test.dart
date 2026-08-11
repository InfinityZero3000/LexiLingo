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

      await recorder.recordGrammarCorrection(
        sourceType: 'topic_chat',
        sourceId: 'session-1',
        original: 'I go there yesterday',
        corrected: 'I went there yesterday',
        explanation: 'Use past tense for completed past actions.',
        skill: 'tense_error',
      );

      final entries = await repository.getEntries();

      expect(entries, hasLength(1));
      expect(entries.single.sourceType, 'topic_chat');
      expect(entries.single.sourceTitle, 'Topic Chat');
      expect(entries.single.selectedAnswer, 'I go there yesterday');
      expect(entries.single.correctAnswer, 'I went there yesterday');
      expect(entries.single.skill, 'tense_error');
      expect(entries.single.createdAt, DateTime(2026, 8, 10));
    });

    test('skips saving when there is no correction text', () async {
      final repository = MistakeNotebookRepository();
      final recorder = ChatMistakeRecorder(repository: repository);

      await recorder.recordGrammarCorrection(
        sourceType: 'lexi_chat',
        sourceId: 'msg-1',
        original: 'something',
        corrected: '   ',
        explanation: '',
      );

      expect(await repository.getEntries(), isEmpty);
    });

    test('defaults skill to grammar when not provided', () async {
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
