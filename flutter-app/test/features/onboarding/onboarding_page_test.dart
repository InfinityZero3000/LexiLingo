import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/presentation/pages/onboarding_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => EasyLocalization.logger.enableLevels = []);

  testWidgets('asks only goal and level, then submits', (tester) async {
    OnboardingAnswers? answers;
    await tester.pumpWidget(
      MaterialApp(home: OnboardingPage(onComplete: (a) async => answers = a)),
    );

    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('onboarding.continueBtn'), findsOneWidget);
    await tester.tap(find.text('onboarding.continueBtn'));
    await tester.pumpAndSettle();

    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('onboarding.interestQuestion'), findsNothing);
    await tester.tap(find.text('onboarding.startLesson'));
    await tester.pumpAndSettle();

    expect(answers, isNotNull);
    expect(answers!.goal, 'career');
    expect(answers!.level, 'A1');
  });

  testWidgets('"not sure" runs the placement test and adopts its level', (
    tester,
  ) async {
    OnboardingAnswers? answers;
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingPage(
          onComplete: (a) async => answers = a,
          onTakePlacementTest: () async {
            opened++;
            return 'B1';
          },
        ),
      ),
    );

    expect(find.text('onboarding.notSureTakeTest'), findsNothing);
    await tester.tap(find.text('onboarding.continueBtn'));
    await tester.pumpAndSettle();

    final link = find.text('onboarding.notSureTakeTest');
    expect(link, findsOneWidget);
    expect(
      tester
          .getSize(find.ancestor(of: link, matching: find.byType(TextButton)))
          .height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.text('onboarding.startLesson'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(answers!.level, 'B1');
  });
}
