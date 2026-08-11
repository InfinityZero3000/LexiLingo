import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
