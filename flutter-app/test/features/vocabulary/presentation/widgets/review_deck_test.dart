import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/flashcard_widget.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/review_deck.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/session_header.dart';

ReviewCardEntity _card(String word) => ReviewCardEntity(
  userVocabulary: UserVocabularyEntity(
    id: word,
    userId: 'u',
    vocabularyId: word,
    status: VocabularyStatus.learning,
    nextReviewDate: DateTime(2026),
    addedAt: DateTime(2026),
  ),
  vocabularyItem: VocabularyItemEntity(
    id: word,
    word: word,
    definition: 'someone who speaks or acts for other people',
    pronunciation: '/ˌreprɪˈzentətɪv/',
    partOfSpeech: 'noun',
    difficultyLevel: 'B2',
    createdAt: DateTime(2026),
  ),
);

ReviewSessionEntity _session({required int total, int reviewed = 0}) =>
    ReviewSessionEntity(
      cards: [for (var i = 0; i < total; i++) _card('word$i')],
      startedAt: DateTime(2026),
      totalCards: total,
      reviewedCards: reviewed,
      correctCount: reviewed,
      totalXpEarned: reviewed * 10,
    );

Future<AnimationController> _pump(
  WidgetTester tester,
  ReviewSessionEntity session, {
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final exit = AnimationController(
    vsync: tester,
    duration: const Duration(milliseconds: 320),
  );
  addTearDown(exit.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        body: RepaintBoundary(
          key: const Key('shot'),
          child: ColoredBox(
            color: const Color(0xFFF4F7FB),
            child: Column(
              children: [
                const SizedBox(height: 12),
                SessionHeader(session: session),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ReviewDeck(
                        behind: session.remainingCards - 1,
                        exit: exit,
                        child: FlashcardWidget(
                          card: session.currentCard!,
                          isFlipped: false,
                          onTap: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  return exit;
}

Finder _layers() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('deck-layer-'),
);

void main() {
  final fontDir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '/usr/local/share/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  final hasFont = File('$fontDir/Roboto-Regular.ttf').existsSync();

  setUpAll(() async {
    // Ahem (the default test font) is a full em wide and reports overflows
    // no device has.
    if (!hasFont) return;
    final loader = FontLoader('Roboto');
    for (final f in ['Regular', 'Bold']) {
      final bytes = File('$fontDir/Roboto-$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  testWidgets('the pile shows what is left, never more than it has', (
    tester,
  ) async {
    await _pump(tester, _session(total: 29));
    expect(_layers(), findsNWidgets(3)); // two fanned + the one that stays put

    await _pump(tester, _session(total: 3, reviewed: 1));
    expect(_layers(), findsNWidgets(1));

    await _pump(tester, _session(total: 3, reviewed: 2));
    expect(_layers(), findsNothing); // last card stands alone
  });

  testWidgets('throwing the top card moves it off and the pile up', (
    tester,
  ) async {
    final exit = await _pump(tester, _session(total: 29));
    final card = find.byType(FlashcardWidget);
    final before = tester.getCenter(card).dx;

    exit.value = 1;
    await tester.pump();

    expect(tester.getCenter(card).dx, lessThan(before - 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('header and deck fit a 320px phone', skip: !hasFont, (
    tester,
  ) async {
    await _pump(tester, _session(total: 120, reviewed: 99), width: 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shot', skip: Platform.environment['DECK_SHOT'] == null, (
    tester,
  ) async {
    debugDisableShadows = false;
    await _pump(tester, _session(total: 29, reviewed: 3));
    debugDisableShadows = true;
    final b = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('shot')),
    );
    await tester.runAsync(() async {
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File(
        Platform.environment['DECK_SHOT']!,
      ).writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
