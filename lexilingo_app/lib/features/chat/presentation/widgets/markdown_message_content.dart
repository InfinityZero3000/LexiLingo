import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget for rendering markdown content in AI messages
class MarkdownMessageContent extends StatelessWidget {
  final String content;
  final bool isDark;

  const MarkdownMessageContent({
    super.key,
    required this.content,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        // Text styles
        p: Theme.of(context).textTheme.bodyMedium,
        h1: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
        h2: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
        h3: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
        
        // Links
        a: const TextStyle(
          color: AppColors.primary,
          decoration: TextDecoration.underline,
        ),
        
        // Code
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
        
        // Lists
        listBullet: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        
        // Blockquote
        blockquoteDecoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(
              color: AppColors.primary,
              width: 4,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.all(12),
        
        // Emphasis
        em: const TextStyle(fontStyle: FontStyle.italic),
        strong: const TextStyle(fontWeight: FontWeight.bold),
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
