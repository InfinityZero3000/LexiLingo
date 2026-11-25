import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/keyboard_dismisser.dart';

void main() {
  Widget app(FocusNode node) => MaterialApp(
    home: KeyboardDismisser(
      child: Scaffold(
        body: Column(
          children: [
            TextField(focusNode: node),
            const Expanded(child: Center(child: Text('outside'))),
          ],
        ),
      ),
    ),
  );

  testWidgets('tapping outside a field drops its focus', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(app(node));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);

    await tester.tap(find.text('outside'));
    await tester.pump();
    expect(node.hasFocus, isFalse);
  });

  testWidgets('tapping the field keeps focus', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(app(node));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);
  });
}
