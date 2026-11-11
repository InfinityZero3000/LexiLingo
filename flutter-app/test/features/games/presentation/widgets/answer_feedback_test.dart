import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/answer_feedback.dart';

class _Loader extends AssetLoader {
  const _Loader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => {
    'games': {
      'answerFeedback': {
        'correctTitle': 'Correct!',
        'wrongTitle': 'Not quite',
        'timeoutTitle': "Time's up",
        'yourAnswer': 'You chose',
        'noAnswer': 'No answer chosen',
        'correctAnswer': 'Correct answer',
        'whyLabel': 'Why',
        'ruleLabel': 'Grammar rule',
        'next': 'Next question',
      },
    },
  };
}

Widget _app(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  path: 'unused',
  fallbackLocale: const Locale('en'),
  startLocale: const Locale('en'),
  useOnlyLangCode: true,
  assetLoader: const _Loader(),
  child: Builder(
    builder: (context) => MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('wrong answer names the pick, the answer and the reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AnswerFeedbackPanel(
          verdict: AnswerVerdict.wrong,
          chosen: 'are',
          correctAnswer: 'is',
          completedText: 'She is a teacher.',
          explanation: "'She' is 3rd person singular.",
          ruleTip: 'To be: He/She/It is.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not quite'), findsOneWidget);
    expect(find.textContaining('You chose'), findsOneWidget);
    expect(find.textContaining('Correct answer'), findsOneWidget);
    expect(find.text('She is a teacher.'), findsOneWidget);
    expect(find.text("'She' is 3rd person singular."), findsOneWidget);
    expect(find.text('To be: He/She/It is.'), findsOneWidget);

    // Nothing dismisses it: the panel is still there long after the old 2s.
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Not quite'), findsOneWidget);
  });

  testWidgets('a correct answer is explained too, without "You chose"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AnswerFeedbackPanel(
          verdict: AnswerVerdict.correct,
          correctAnswer: 'is',
          explanation: 'Same text',
          ruleTip: 'Same text',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Correct!'), findsOneWidget);
    expect(find.textContaining('You chose'), findsNothing);
    expect(find.text('Same text'), findsOneWidget);
  });

  testWidgets('timeout without a pick says no answer was chosen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AnswerFeedbackPanel(
          verdict: AnswerVerdict.timeout,
          chosen: '',
          correctAnswer: 'is',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Time's up"), findsOneWidget);
    expect(find.textContaining('No answer chosen'), findsOneWidget);
  });

  testWidgets('GameNextBar fires its callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(GameNextBar(label: 'Next question', onPressed: () => taps++)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next question'));
    expect(taps, 1);
  });
}
