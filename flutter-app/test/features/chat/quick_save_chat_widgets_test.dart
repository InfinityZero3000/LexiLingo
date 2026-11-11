import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/quick_save_selection_area.dart';
import 'package:lexilingo_app/features/chat/domain/entities/story.dart';
import 'package:lexilingo_app/features/chat/presentation/pages/topic_chat_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart';

class _EmptyVocabRepository implements VocabRepository {
  @override
  Future<Either<Failure, void>> addWord(VocabWord word) async =>
      const Right(null);

  @override
  Future<Either<Failure, List<VocabWord>>> getWords() async => const Right([]);
}

void main() {
  testWidgets('Lexi user and assistant messages support quick-save selection', (
    tester,
  ) async {
    final now = DateTime(2026, 6, 6);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              LexiDialogueBubble(
                message: LexiMessage(
                  id: 'assistant-1',
                  role: 'assistant',
                  content: 'Try the word resilient.',
                  timestamp: now,
                ),
              ),
              LexiDialogueBubble(
                message: LexiMessage(
                  id: 'user-1',
                  role: 'user',
                  content: 'I want to save resilient.',
                  timestamp: now,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(QuickSaveSelectionArea), findsNWidgets(2));
  });

  testWidgets('Topic vocabulary preview exposes a direct save action', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    final repo = _EmptyVocabRepository();
    final vocabProvider = VocabProvider(
      getWordsUseCase: GetWordsUseCase(repo),
      addWordUseCase: AddWordUseCase(repo),
    );
    addTearDown(vocabProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<VocabProvider>.value(
        value: vocabProvider,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: VocabularyPreviewSheet(
                vocabulary: const [
                  VocabularyItem(
                    term: 'resilient',
                    definition: 'able to recover quickly',
                    exampleInStory: 'She remained resilient.',
                    partOfSpeech: 'adjective',
                  ),
                ],
                scrollController: scrollController,
                sourceReference: 'story-1',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('vocabulary.saveToVocabulary'));
    await tester.pumpAndSettle();

    expect(find.text('vocabulary.saveWord'), findsOneWidget);
    expect(find.text('resilient'), findsWidgets);
  });
}
