import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/chat/presentation/widgets/chat_rich_blocks.dart';
import 'package:lexilingo_app/features/chat/presentation/widgets/markdown_message_content.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders a GFM table without throwing', (tester) async {
    const content = '''
| Form | Use |
| --- | --- |
| Present Simple | habits |
| Present Continuous | now |
''';
    await tester.pumpWidget(
      _wrap(const MarkdownMessageContent(content: content, isDark: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Form'), findsOneWidget);
    expect(find.text('Present Simple'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a chart fence as a chart, not literal code', (
    tester,
  ) async {
    const content = '''
Here is your progress:
```chart
{"type":"bar","title":"XP this week","labels":["Mon","Tue"],"series":[{"name":"XP","values":[10,20]}]}
```
''';
    await tester.pumpWidget(
      _wrap(const MarkdownMessageContent(content: content, isDark: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('XP this week'), findsOneWidget);
    // The raw JSON must not leak through as visible text.
    expect(find.textContaining('"type":"bar"'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed chart JSON degrades gracefully (no crash)', (
    tester,
  ) async {
    const content = '```chart\nnot valid json\n```';
    await tester.pumpWidget(
      _wrap(const MarkdownMessageContent(content: content, isDark: false)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a regular fenced code block still renders as code', (
    tester,
  ) async {
    const content = '```python\nprint("hi")\n```';
    await tester.pumpWidget(
      _wrap(const MarkdownMessageContent(content: content, isDark: false)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('print'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('rich blocks', () {
    Future<void> pump(WidgetTester t, String content) async {
      await t.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: MarkdownMessageContent(content: content, isDark: false),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('callout renders bold, not literal asterisks', (t) async {
      await pump(
        t,
        'Intro\n```callout\ntip: Use **Past Simple** for finished actions.\n```\nOutro',
      );
      expect(find.textContaining('Past Simple', findRichText: true), findsOneWidget);
      expect(find.textContaining('**', findRichText: true), findsNothing);
      expect(find.textContaining('```', findRichText: true), findsNothing);
      expect(find.text('Intro', findRichText: true), findsOneWidget);
      expect(find.text('Outro', findRichText: true), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('vocab, fix and steps render their fields', (t) async {
      await pump(
        t,
        '```vocab\nword: achieve\npos: verb\nmeaning: to succeed in doing something\n'
        'example: She **achieved** her goal.\n```\n'
        '```fix\nwrong: I have studied there in 2020.\nright: I **studied** there in 2020.\n'
        'why: A finished time needs Past Simple.\n```\n'
        '```steps\nPast Simple | finished actions\nPresent Perfect | results now\n```\n',
      );
      for (final s in [
        'achieve',
        'verb',
        'I have studied there in 2020.',
        'Past Simple',
        'Present Perfect',
        'results now',
      ]) {
        expect(find.textContaining(s, findRichText: true), findsWidgets, reason: s);
      }
      expect(find.textContaining('word:', findRichText: true), findsNothing);
      expect(find.textContaining('**', findRichText: true), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('vocab card shows a save button only when a source is given', (
      t,
    ) async {
      const md = '```vocab\nword: achieve\nmeaning: to succeed\n```';
      await pump(t, md);
      expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);

      await t.pumpWidget(
        _wrap(
          const MarkdownMessageContent(
            content: md,
            isDark: false,
            saveSourceType: 'topic_chat',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    });

    testWidgets('malformed blocks render nothing and never crash', (t) async {
      await pump(
        t,
        '```vocab\nmeaning only\n```\n```fix\nwrong: x\n```\n```steps\n\n```',
      );
      expect(t.takeException(), isNull);
    });
  });

  group('splitChatBlocks', () {
    test('plain text stays one markdown segment', () {
      final s = splitChatBlocks('hello **x**');
      expect(s.length, 1);
      expect(s.single.kind, isNull);
    });

    test('an unfinished fence (streaming) is held back', () {
      final s = splitChatBlocks('Hi\n```callout\ntip: par');
      expect(s.length, 1);
      expect(s.single.markdown, 'Hi\n');
    });

    test('ordinary code fences are left to markdown', () {
      expect(splitChatBlocks('```python\nx=1\n```').single.kind, isNull);
    });
  });
}
