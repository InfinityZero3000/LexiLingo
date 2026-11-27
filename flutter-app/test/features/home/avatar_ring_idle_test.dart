import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';

Widget _header({bool disableAnimations = false, bool tickersEnabled = true}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        home: TickerMode(
          enabled: tickersEnabled,
          child: Scaffold(
            body: PersonalizedGreetingHeader(userName: 'Lan', totalXP: 10),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the avatar ring turns once and then lets the page go idle', (
    tester,
  ) async {
    await tester.pumpWidget(_header());

    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduced motion never starts the ring', (tester) async {
    await tester.pumpWidget(_header(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a hidden tab schedules no frames for the ring', (tester) async {
    await tester.pumpWidget(_header(tickersEnabled: false));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
