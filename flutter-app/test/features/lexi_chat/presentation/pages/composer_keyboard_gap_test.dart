import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MainScreen extends its body behind the bottom nav, so every tab inherits a
/// bottom padding of nav + home indicator. A leaf SafeArea that keeps that
/// padding while the keyboard is open leaves a gap above the keyboard.
Widget _app({required bool keepBottomWhenKeyboard}) {
  return MediaQuery(
    data: const MediaQueryData(
      size: Size(390, 844),
      padding: EdgeInsets.only(top: 47, bottom: 34),
      viewInsets: EdgeInsets.only(bottom: 300),
    ),
    child: MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        extendBody: true,
        bottomNavigationBar: const SizedBox(height: 60),
        body: Builder(
          builder: (context) => Scaffold(
            body: SafeArea(
              bottom: keepBottomWhenKeyboard
                  ? true
                  : MediaQuery.viewInsetsOf(context).bottom == 0,
              child: const Column(
                children: [
                  Expanded(child: SizedBox.expand()),
                  SizedBox(key: Key('composer'), height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

double _gapAboveKeyboard(WidgetTester tester) {
  final composerBottom = tester
      .getBottomLeft(find.byKey(const Key('composer')))
      .dy;
  return (844 - 300) - composerBottom;
}

void main() {
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('a SafeArea that keeps the nav padding leaves a gap', (t) async {
    phone(t);
    await t.pumpWidget(_app(keepBottomWhenKeyboard: true));
    expect(_gapAboveKeyboard(t), greaterThan(40));
  });

  testWidgets(
    'dropping the bottom inset while the keyboard is open closes it',
    (t) async {
      phone(t);
      await t.pumpWidget(_app(keepBottomWhenKeyboard: false));
      expect(_gapAboveKeyboard(t), 0);
    },
  );
}
