import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

LexiMessage _user({bool uncertain = false}) => LexiMessage(
  id: 'u',
  role: 'user',
  content: 'I goed there',
  timestamp: DateTime(2026),
  heardUncertain: uncertain,
);

void main() {
  testWidgets('the mis-heard chip appears only for an unsure transcript', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(LexiDialogueBubble(message: _user(), onMisheardTap: () {})),
    );
    expect(find.text('lexiChat.voice.misheardChip'), findsNothing);

    await tester.pumpWidget(
      _host(
        LexiDialogueBubble(
          message: _user(uncertain: true),
          onMisheardTap: () {},
        ),
      ),
    );
    expect(find.text('lexiChat.voice.misheardChip'), findsOneWidget);
  });

  testWidgets('its label stays readable instead of yellow on pale yellow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LexiDialogueBubble(
          message: _user(uncertain: true),
          onMisheardTap: () {},
        ),
      ),
    );
    final label = tester.widget<Text>(find.text('lexiChat.voice.misheardChip'));
    expect(label.style!.color, AppColors.textDark);

    await tester.pumpWidget(
      _host(
        LexiDialogueBubble(
          message: _user(uncertain: true),
          onMisheardTap: () {},
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();
    final dark = tester.widget<Text>(find.text('lexiChat.voice.misheardChip'));
    expect(dark.style!.color, Colors.white);
  });

  testWidgets('a long translated chip label wraps instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        LexiDialogueBubble(
          message: _user(uncertain: true),
          onMisheardTap: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a covered voice reply reveals itself on tap', (tester) async {
    var revealed = 0;
    final reply = LexiMessage(
      id: 'voice_assistant_t1',
      role: 'assistant',
      content: 'Went.',
      timestamp: DateTime(2026),
    );
    await tester.pumpWidget(
      _host(
        LexiDialogueBubble(
          message: reply,
          captionHidden: true,
          onRevealCaption: () => revealed++,
        ),
      ),
    );
    expect(find.text('Went.'), findsNothing);
    await tester.tap(find.text('lexiChat.voice.tapToReveal'));
    expect(revealed, 1);
  });
}
