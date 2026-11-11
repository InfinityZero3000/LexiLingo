import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_rich_blocks.dart';

/// Widget for rendering markdown content in AI messages.
///
/// Supports GFM tables plus fenced `chart`, `callout`, `vocab`, `fix` and
/// `steps` blocks rendered as cards — see [splitChatBlocks].
class MarkdownMessageContent extends StatelessWidget {
  final String content;
  final bool isDark;
  final bool selectable;

  /// Overrides the base paragraph style (font size/height/color). Other
  /// styles (headings, code, table, ...) still derive from [Theme].
  final TextStyle? baseTextStyle;

  /// Background highlight applied to **bold** / *italic* runs, if desired.
  final Color? highlightColor;

  /// When set, `vocab` cards get a "save word" button tagged with this source.
  final String? saveSourceType;
  final String? saveSourceReference;

  const MarkdownMessageContent({
    super.key,
    required this.content,
    required this.isDark,
    this.selectable = true,
    this.baseTextStyle,
    this.highlightColor,
    this.saveSourceType,
    this.saveSourceReference,
  });

  @override
  Widget build(BuildContext context) {
    final segments = splitChatBlocks(content);
    if (segments.length == 1 && segments.first.kind == null) {
      return _markdown(context, segments.first.markdown!);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in segments)
          s.kind == null ? _markdown(context, s.markdown!) : buildChatBlock(
                s,
                saveSource: saveSourceType == null
                    ? null
                    : (type: saveSourceType!, ref: saveSourceReference),
              ),
      ],
    );
  }

  Widget _markdown(BuildContext context, String data) {
    final theme = Theme.of(context);
    final p = baseTextStyle ?? theme.textTheme.bodyMedium;

    return MarkdownBody(
      data: data,
      selectable: selectable,
      // fromTheme() fills in every style (table, checkbox, ...) with sane
      // defaults; the bare MarkdownStyleSheet() constructor leaves them
      // null, which flutter_markdown force-unwraps and crashes on for
      // tables specifically.
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: p,
        h1: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
        h2: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        h3: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),

        a: (p ?? const TextStyle()).copyWith(
          color: AppColorRoles.primary(isDark),
          decoration: TextDecoration.underline,
        ),

        code: TextStyle(
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[200],
          color: isDark ? Colors.lightGreen : Colors.green[800],
          fontFamily: 'monospace',
          fontSize: 14,
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),

        listBullet: (p ?? const TextStyle()).copyWith(fontWeight: FontWeight.bold),

        blockquoteDecoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
        ),
        blockquotePadding: const EdgeInsets.all(12),

        em: highlightColor == null
            ? const TextStyle(fontStyle: FontStyle.italic)
            : (p ?? const TextStyle()).copyWith(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                backgroundColor: highlightColor,
              ),
        strong: highlightColor == null
            ? const TextStyle(fontWeight: FontWeight.bold)
            : (p ?? const TextStyle()).copyWith(
                fontWeight: FontWeight.w700,
                backgroundColor: highlightColor,
              ),

        // Tables — for comparisons ("so sánh X vs Y"). IntrinsicColumnWidth
        // is what makes flutter_markdown wrap the table in a horizontal
        // scroll view, which mobile-width bubbles need.
        tableHead: (p ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700),
        tableBody: p,
        tableBorder: TableBorder.all(
          color: isDark ? AppColors.borderDarkSoft : AppColors.grey200,
          width: 1,
          borderRadius: BorderRadius.circular(6),
        ),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      onTapLink: (text, href, title) {
        if (href != null) {
          _launchURL(href);
        }
      },
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
