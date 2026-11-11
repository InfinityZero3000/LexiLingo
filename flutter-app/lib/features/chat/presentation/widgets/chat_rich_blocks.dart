import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/quick_save_word_sheet.dart';

import 'chat_chart_block.dart';
import 'markdown_message_content.dart';

/// One piece of an AI message: plain markdown, or a fenced rich block.
class ChatSegment {
  final String? markdown;
  final String? kind;
  final String body;

  const ChatSegment.markdown(this.markdown) : kind = null, body = '';
  const ChatSegment.block(this.kind, this.body) : markdown = null;
}

const _kinds = 'chart|callout|vocab|fix|steps';
final _closedFence = RegExp(
  '```($_kinds)[ \\t]*\\n(.*?)```',
  dotAll: true,
);
final _openFence = RegExp('```($_kinds)[ \\t]*(\\n|\$)');

/// Splits [content] so rich fences render as their own widgets instead of
/// sitting inside the markdown code-block box. A fence still being streamed
/// (no closing ```) is dropped until it completes.
List<ChatSegment> splitChatBlocks(String content) {
  final out = <ChatSegment>[];
  var pos = 0;
  for (final m in _closedFence.allMatches(content)) {
    if (m.start > pos) out.add(ChatSegment.markdown(content.substring(pos, m.start)));
    out.add(ChatSegment.block(m.group(1)!, m.group(2)!.trim()));
    pos = m.end;
  }
  var tail = content.substring(pos);
  final open = _openFence.firstMatch(tail);
  if (open != null) tail = tail.substring(0, open.start);
  if (tail.trim().isNotEmpty) out.add(ChatSegment.markdown(tail));
  return out;
}

/// [saveSource] enables the bookmark on vocab cards (`sourceType`, `sourceReference`).
Widget buildChatBlock(ChatSegment s, {({String type, String? ref})? saveSource}) => switch (s.kind) {
  'chart' => ChatChartCard(rawSpec: s.body),
  'callout' => ChatCalloutCard(body: s.body),
  'vocab' => ChatVocabCard(body: s.body, saveSource: saveSource),
  'fix' => ChatFixCard(body: s.body),
  'steps' => ChatStepsCard(body: s.body),
  _ => const SizedBox.shrink(),
};

/// `key: value` lines → map (keys lower-cased, first colon splits).
Map<String, String> parseChatFields(String body) {
  final out = <String, String>{};
  for (final line in body.split('\n')) {
    final i = line.indexOf(':');
    if (i <= 0) continue;
    final v = line.substring(i + 1).trim();
    if (v.isNotEmpty) out[line.substring(0, i).trim().toLowerCase()] = v;
  }
  return out;
}

Widget _md(String text, bool isDark, {double size = 14, Color? color}) =>
    MarkdownMessageContent(
      content: text,
      isDark: isDark,
      selectable: false,
      baseTextStyle: TextStyle(
        fontSize: size,
        height: 1.5,
        color: color ?? AppColorRoles.textPrimary(isDark),
      ),
    );

class _Card extends StatelessWidget {
  final Color accent;
  final Widget child;
  const _Card({required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// ```callout — first line is `tip|warning|note|example` (optionally followed
/// by text); the rest is markdown.
class ChatCalloutCard extends StatelessWidget {
  final String body;
  const ChatCalloutCard({super.key, required this.body});

  static final _head = RegExp(
    r'^(tip|warning|note|example)\b[:：]?[ \t]*',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final isDark = _dark(context);
    final m = _head.firstMatch(body);
    final kind = m?.group(1)?.toLowerCase() ?? 'note';
    final text = (m == null ? body : body.substring(m.end)).trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final (icon, color) = switch (kind) {
      'tip' => (Icons.lightbulb_rounded, AppColors.warningDark),
      'warning' => (Icons.warning_amber_rounded, AppColors.errorDark),
      'example' => (Icons.format_quote_rounded, AppColors.greenSuccess),
      _ => (Icons.info_rounded, AppColorRoles.primary(isDark)),
    };
    return _Card(
      accent: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(child: _md(text, isDark)),
        ],
      ),
    );
  }
}

/// ```vocab — fields: word, pos, ipa, meaning, vi, example.
class ChatVocabCard extends StatelessWidget {
  final String body;
  final ({String type, String? ref})? saveSource;
  const ChatVocabCard({super.key, required this.body, this.saveSource});

  @override
  Widget build(BuildContext context) {
    final isDark = _dark(context);
    final f = parseChatFields(body);
    final word = f['word'];
    if (word == null) return const SizedBox.shrink();
    final primary = AppColorRoles.primary(isDark);
    final muted = AppColorRoles.textSecondary(isDark);

    return _Card(
      accent: primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                word,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
              if (f['pos'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(f['pos']!, style: TextStyle(fontSize: 12, color: primary)),
                ),
              if (f['ipa'] != null)
                Text(f['ipa']!, style: TextStyle(fontSize: 12, color: muted)),
              if (saveSource != null)
                InkWell(
                  onTap: () => showQuickSaveWordSheet(
                    context,
                    word: word,
                    sourceType: saveSource!.type,
                    sourceReference: saveSource!.ref,
                    contextSentence: f['example'],
                    definition: f['meaning'],
                    translation: f['vi'],
                    partOfSpeech: f['pos'],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.bookmark_add_outlined, size: 20, color: primary),
                  ),
                ),
            ],
          ),
          if (f['meaning'] != null) ...[
            const SizedBox(height: 8),
            _md(f['meaning']!, isDark),
          ],
          if (f['vi'] != null) ...[
            const SizedBox(height: 4),
            _md(f['vi']!, isDark, color: primary),
          ],
          if (f['example'] != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote_rounded, size: 16, color: muted),
                const SizedBox(width: 4),
                Expanded(child: _md(f['example']!, isDark, size: 12, color: muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// ```fix — fields: wrong, right, why.
class ChatFixCard extends StatelessWidget {
  final String body;
  const ChatFixCard({super.key, required this.body});

  @override
  Widget build(BuildContext context) {
    final isDark = _dark(context);
    final f = parseChatFields(body);
    final wrong = f['wrong'];
    final right = f['right'];
    if (wrong == null || right == null) return const SizedBox.shrink();
    final bad = isDark ? AppColors.errorBright : AppColors.errorDark;
    final good = isDark ? AppColors.greenSuccessBright : AppColors.greenSuccess;

    Widget line(IconData icon, Color color, Widget text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(child: text),
      ],
    );

    return _Card(
      accent: good,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(
            Icons.close_rounded,
            bad,
            Text(
              wrong,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: bad,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
          const SizedBox(height: 4),
          line(Icons.check_rounded, good, _md(right, isDark, color: good)),
          if (f['why'] != null) ...[
            const SizedBox(height: 8),
            _md(f['why']!, isDark, size: 12, color: AppColorRoles.textSecondary(isDark)),
          ],
        ],
      ),
    );
  }
}

/// ```steps — one `Title | detail` per line, rendered as a numbered timeline.
class ChatStepsCard extends StatelessWidget {
  final String body;
  const ChatStepsCard({super.key, required this.body});

  @override
  Widget build(BuildContext context) {
    final isDark = _dark(context);
    final steps = <(String, String)>[
      for (final line in body.split('\n'))
        if (line.trim().isNotEmpty)
          (
            line.split('|').first.trim(),
            line.contains('|') ? line.substring(line.indexOf('|') + 1).trim() : '',
          ),
    ];
    if (steps.isEmpty) return const SizedBox.shrink();
    final primary = AppColorRoles.primary(isDark);

    return _Card(
      accent: primary,
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.surfaceDarkInk : AppColors.textInverted,
                            ),
                          ),
                        ),
                        if (i < steps.length - 1)
                          Expanded(
                            child: Container(width: 2, color: primary.withValues(alpha: 0.35)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 12 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _md('**${steps[i].$1}**', isDark),
                          if (steps[i].$2.isNotEmpty)
                            _md(steps[i].$2, isDark, size: 12, color: AppColorRoles.textSecondary(isDark)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
