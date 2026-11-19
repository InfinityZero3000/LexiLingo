import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> _pump(WidgetTester tester, ThemeData Function() theme, bool correct) =>
    tester.pumpWidget(
      MaterialApp(
        theme: theme(),
        home: Scaffold(
          body: ExerciseExplanationCard(
            explanation: 'Good morning is used early in the day.',
            isCorrect: correct,
            correctAnswer: correct ? null : 'Chào buổi sáng',
          ),
        ),
      ),
    );

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() => EasyLocalization.logger.enableLevels = []);

  // Built inside each test: AppTheme asks google_fonts for a font as it builds.
  final themes = <String, ThemeData Function()>{
    'light': () => AppTheme.lightTheme,
    'dark': () => AppTheme.darkTheme,
  };
  for (final entry in themes.entries) {
    for (final correct in [true, false]) {
      testWidgets(
        '${entry.key} theme, ${correct ? 'correct' : 'wrong'} answer: the text reads at 4.5:1 or better',
        (tester) async {
          await _pump(tester, entry.value, correct);

          final box = tester.widget<AnimatedContainer>(
            find.byType(AnimatedContainer),
          );
          final bg = (box.decoration! as BoxDecoration).color!;
          final texts = tester.widgetList<Text>(find.byType(Text)).toList();

          expect(texts, isNotEmpty);
          for (final text in texts) {
            final fg = text.style!.color!;
            expect(
              _contrast(Color.alphaBlend(bg, Colors.white), fg),
              greaterThanOrEqualTo(4.5),
              reason: '"${text.data}" ${fg.toARGB32().toRadixString(16)} on '
                  '${bg.toARGB32().toRadixString(16)}',
            );
          }
        },
      );
    }
  }

  group('scrolling into view', () {
    Future<ScrollController> pumpTall(
      WidgetTester tester, {
      bool disableAnimations = false,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(375, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(375, 500),
              disableAnimations: disableAnimations,
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: [
                    const SizedBox(height: 700),
                    ExerciseExplanationCard(
                      explanation: 'Good morning is used early in the day.',
                      isCorrect: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('an explanation that appears below the fold is scrolled to', (
      tester,
    ) async {
      final controller = await pumpTall(tester);
      expect(controller.offset, 0, reason: 'not scrolled before the first frame ends');

      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
      final card = tester.getRect(find.byType(ExerciseExplanationCard));
      expect(card.bottom, lessThanOrEqualTo(500));
    });

    testWidgets('reduced motion jumps instead of animating', (tester) async {
      final controller = await pumpTall(tester, disableAnimations: true);

      await tester.pump();
      await tester.pump();

      expect(controller.offset, greaterThan(0));
    });
  });
}
