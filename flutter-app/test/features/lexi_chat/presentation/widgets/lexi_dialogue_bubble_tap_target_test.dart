import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart';

void main() {
  testWidgets('action chips on a phone are at least 44px tall', (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final message = LexiMessage(
      id: 'l',
      role: 'assistant',
      content: 'Hello there',
      timestamp: DateTime(2026),
      audioBase64: 'AAAA',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LexiDialogueBubble(message: message, onPlayAudio: () {}),
        ),
      ),
    );

    final chip = find.ancestor(
      of: find.text('lexiChat.listenButton'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(chip.first).height, greaterThanOrEqualTo(44));
  });
}
