import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/vocab_word_detail_sheet.dart';
import 'package:provider/provider.dart';

class _EmptyVocabRepository implements VocabRepository {
  @override
  Future<Either<Failure, void>> addWord(VocabWord word) async =>
      const Right(null);

  @override
  Future<Either<Failure, List<VocabWord>>> getWords() async => const Right([]);
}

void main() {
  testWidgets('add-to-collection sheet offers inline creation with no decks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The flashcard header row overflows only under the test font with raw i18n keys.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('RenderFlex overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

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
                onPressed: () => showVocabWordDetail(
                  context,
                  VocabWord(
                    id: 1,
                    userVocabularyId: 'uv1',
                    word: 'implement',
                    definition: 'to put into effect',
                  ),
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
    await tester.tap(find.text('vocabulary.addToDeck'));
    await tester.pumpAndSettle();

    expect(find.text('vocabulary.noDecksFound'), findsOneWidget);
    await tester.tap(find.text('vocabulary.newCollection'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('vocabulary.noDecksFound'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
