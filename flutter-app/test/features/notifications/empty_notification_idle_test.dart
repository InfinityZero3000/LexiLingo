import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/badge_generator.dart';
import 'package:lexilingo_app/features/notifications/presentation/widgets/empty_notification_widget.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('the empty notifications illustration settles', (tester) async {
    await tester.pumpWidget(_app(const EmptyNotificationWidget()));

    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a badge shines once and then stops repainting', (tester) async {
    await tester.pumpWidget(
      _app(const Center(child: GeneratedBadge(config: BadgeConfig()))),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(tester.hasRunningAnimations, isFalse);
  });
}
