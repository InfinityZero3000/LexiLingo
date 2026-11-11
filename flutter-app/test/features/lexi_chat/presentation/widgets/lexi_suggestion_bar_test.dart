import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/lexi_chat/data/lexi_reply_suggester.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_suggestion_bar.dart';

class _FakeSuggester extends LexiReplySuggester {
  int calls = 0;
  _FakeSuggester() : super(apiClient: ApiClient(baseUrl: 'http://localhost'));

  @override
  Future<List<String>> suggest(String lexiText) async {
    calls++;
    return const ['I walk to work.', 'By bus.'];
  }
}

LexiMessage _msg(String id, String content) => LexiMessage(
  id: id,
  role: 'assistant',
  content: content,
  timestamp: DateTime(2026),
);

void main() {
  late _FakeSuggester fake;

  setUp(() {
    fake = _FakeSuggester();
    sl.registerSingleton<LexiReplySuggester>(fake);
  });
  tearDown(() => sl.reset());

  Widget host(LexiMessage m, ValueChanged<String> onSend) => MaterialApp(
    home: Scaffold(
      body: LexiSuggestionBar(
        message: m,
        nativeLanguage: 'en',
        isDark: false,
        onSend: onSend,
      ),
    ),
  );

  testWidgets('a question shows fetched answers and tapping one sends it', (
    t,
  ) async {
    String? sent;
    await t.pumpWidget(
      host(_msg('1', 'How do you get to work?'), (s) => sent = s),
    );
    await t.pumpAndSettle();

    expect(find.text('I walk to work.'), findsOneWidget);
    await t.tap(find.text('By bus.'));
    expect(sent, 'By bus.');
  });

  testWidgets('a statement fetches nothing', (t) async {
    await t.pumpWidget(host(_msg('2', 'Great job today!'), (_) {}));
    await t.pumpAndSettle();
    expect(fake.calls, 0);
    expect(find.text('I walk to work.'), findsNothing);
  });
}
