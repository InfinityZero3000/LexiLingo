import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/presentation/pages/welcome_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Untranslated keys are wider than real copy, so only vertical overflow
  // says anything about the banner.
  void expectNoVerticalOverflow(WidgetTester tester) {
    final error = tester.takeException();
    expect(error?.toString() ?? '', isNot(contains('bottom')));
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomePage(onGetStarted: () {}, onSkip: () {}),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  for (final size in const [Size(390, 844), Size(360, 640), Size(1280, 800)]) {
    testWidgets('fits without scrolling at $size', (tester) async {
      await pump(tester, size);
      expectNoVerticalOverflow(tester);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  }

  testWidgets('very short screens scroll instead of squeezing', (tester) async {
    await pump(tester, const Size(360, 420));
    expectNoVerticalOverflow(tester);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
