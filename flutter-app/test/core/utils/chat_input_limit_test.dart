import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/utils/chat_input_limit.dart';

void main() {
  Future<TextEditingController> pumpField(WidgetTester tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            maxLines: 4,
            inputFormatters: chatInputFormatters,
            buildCounter: buildChatInputCounter,
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('typing past the limit is truncated at 4000', (tester) async {
    final controller = await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'a' * 4500);
    await tester.pump();
    expect(controller.text.length, kMaxChatMessageChars);
  });

  testWidgets('a paste is cut to the limit, not rejected whole', (
    tester,
  ) async {
    final controller = await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'x' * 10);
    await tester.enterText(find.byType(TextField), 'y' * 9000);
    await tester.pump();
    expect(controller.text, 'y' * kMaxChatMessageChars);
  });

  testWidgets('limit counts code points and never splits a surrogate pair', (
    tester,
  ) async {
    final controller = await pumpField(tester);
    await tester.enterText(find.byType(TextField), '😀' * 4500);
    await tester.pump();
    expect(controller.text.runes.length, kMaxChatMessageChars);
  });

  testWidgets('counter stays hidden until near the limit', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'a' * 100);
    await tester.pump();
    expect(find.textContaining('/ $kMaxChatMessageChars'), findsNothing);

    await tester.enterText(find.byType(TextField), 'a' * kChatCounterThreshold);
    await tester.pump();
    expect(
      find.text('$kChatCounterThreshold / $kMaxChatMessageChars'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'a' * 5000);
    await tester.pump();
    final counter = tester.widget<Text>(
      find.text('$kMaxChatMessageChars / $kMaxChatMessageChars'),
    );
    expect(
      counter.style?.color,
      ThemeData().colorScheme.error,
      reason: 'at the limit the counter turns to the error colour',
    );
  });

  test('isMessageTooLongError recognises a 422 and nothing else', () {
    expect(
      isMessageTooLongError(
        const ServerException(
          'POST stream /lexi/stream failed with status 422: x',
        ),
      ),
      isTrue,
    );
    expect(
      isMessageTooLongError(const ServerException('failed with status 500')),
      isFalse,
    );
    expect(isMessageTooLongError('Unauthorized 401'), isFalse);
  });
}
