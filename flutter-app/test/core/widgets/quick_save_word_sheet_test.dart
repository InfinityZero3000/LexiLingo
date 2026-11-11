import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/widgets/quick_save_word_sheet.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:provider/provider.dart';

class _EmptyVocabRepository implements VocabRepository {
  @override
  Future<Either<Failure, void>> addWord(VocabWord word) async =>
      const Right(null);

  @override
  Future<Either<Failure, List<VocabWord>>> getWords() async => const Right([]);
}

void main() {
  testWidgets('sheet lets the learner start a new collection inline', (
    tester,
  ) async {
    final repo = _EmptyVocabRepository();
    final vocab = VocabProvider(
      getWordsUseCase: GetWordsUseCase(repo),
      addWordUseCase: AddWordUseCase(repo),
    );
    addTearDown(vocab.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<VocabProvider>.value(
        value: vocab,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showQuickSaveWordSheet(
                  context,
                  word: 'resilient',
                  sourceType: 'news',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('vocabulary.newCollection'), findsOneWidget);

    await tester.tap(find.text('vocabulary.newCollection'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.shuffle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('deck colours always resolve and get a distinct gradient stop', () {
    expect(deckColorFromHex('#E91E63'), const Color(0xFFE91E63));
    expect(deckColorFromHex('garbage'), const Color(0xFF2196F3));
    final g = deckGradient(const Color(0xFF2196F3));
    expect(g.colors.first, isNot(g.colors.last));
  });
}
