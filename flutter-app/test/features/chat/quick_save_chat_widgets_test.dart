import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/quick_save_selection_area.dart';
import 'package:lexilingo_app/features/chat/data/models/story_model.dart';
import 'package:lexilingo_app/features/chat/presentation/pages/topic_chat_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart';

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

    await tester.pumpWidget(
      MaterialApp(
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
    );

    await tester.tap(find.byTooltip('Save to Vocabulary'));
    await tester.pumpAndSettle();

    expect(find.text('Save Word'), findsOneWidget);
    expect(find.text('resilient'), findsWidgets);
  });
}
