import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/game_icon.dart';

void main() {
  testWidgets('AppGameIcon renders Material fallback without image assets', (
    tester,
  ) async {
    const icon = AppGameIcon(GameIcon.flashcards, size: 32);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: icon)));

    expect(find.byType(Icon), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(icon.hasCustomAsset, isFalse);
  });
}
