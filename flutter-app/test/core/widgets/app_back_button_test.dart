import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';

void main() {
  testWidgets('is borderless and keeps an accessible touch target', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppBackButton(onPressed: () => pressed = true)),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.style?.side?.resolve({}), BorderSide.none);
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    expect(pressed, isTrue);
  });

  testWidgets('defaults to maybePop', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: AppBackButton()),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
  });
}
