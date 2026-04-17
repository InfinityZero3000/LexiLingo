import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/quick_save_word_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/news_entities.dart';
import '../providers/news_provider.dart';

/// News Detail Screen — full article with vocabulary highlighting.
///
/// Features:
/// - Full article text with tappable highlighted vocabulary words
/// - Reading progress indicator
/// - "Take Quiz" button appears after scrolling ≥90%
/// - CEFR level badge and reading time
///
/// Phase 2: News Reading.
class NewsDetailScreen extends StatefulWidget {
  final NewsArticle article;

  const NewsDetailScreen({super.key, required this.article});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  final _scrollController = ScrollController();
  double _readingProgress = 0.0;
  bool _showQuizButton = false;
  String? _fullContent;
  bool _isLoadingFullContent = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_trackProgress);
    _loadFullContentIfNeeded();
  }

  /// Auto-fetch full article content if the current content looks truncated.
  void _loadFullContentIfNeeded() {
    final content = widget.article.content;
    // NewsAPI free tier truncates to ~200 chars, often ending with "[+XXXX chars]"
    final isTruncated =
        content.length < 500 || RegExp(r'\[\+\d+ chars\]$').hasMatch(content);
    if (isTruncated && widget.article.url.isNotEmpty) {
      _isLoadingFullContent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final provider = context.read<NewsProvider>();
          final fullContent = await provider.loadFullContent(
            widget.article.url,
          );
          if (mounted &&
              fullContent != null &&
              fullContent.length > content.length) {
            setState(() {
              _fullContent = fullContent;
              _isLoadingFullContent = false;
            });
          } else {
            if (mounted) setState(() => _isLoadingFullContent = false);
          }
        } catch (_) {
          if (mounted) setState(() => _isLoadingFullContent = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _trackProgress() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    setState(() {
      _readingProgress = (_scrollController.offset / maxScroll).clamp(0.0, 1.0);
      if (_readingProgress >= 0.9 && !_showQuizButton) {
        _showQuizButton = true;
      }
    });
  }

  void _onWordTap(String word, {String? contextSentence}) {
    final cleanWord = word
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .toLowerCase()
        .trim();
    if (cleanWord.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildDictionarySheet(
        cleanWord,
        contextSentence: contextSentence,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(widget.article.cefrLevel);

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // ── App Bar with Image ──
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                backgroundColor: isDark
                    ? AppColors.backgroundDark
                    : Colors.white,
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.article.imageUrl.isNotEmpty)
                        Image.network(
                          widget.article.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: cefrColor.withValues(alpha: 0.2),
                          ),
                        )
                      else
                        Container(color: cefrColor.withValues(alpha: 0.2)),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                      // CEFR badge + meta
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: cefrColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                widget.article.cefrLevel,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.surface,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.article.readingTimeMin} min read',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              widget.article.sourceName,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Article Content ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        widget.article.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),

                      // Author and date
                      if (widget.article.author.isNotEmpty ||
                          widget.article.publishedAt.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (widget.article.author.isNotEmpty)
                              Text(
                                'By ${widget.article.author}',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : AppColors.textGrey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (widget.article.author.isNotEmpty &&
                                widget.article.publishedAt.isNotEmpty)
                              Text(
                                ' · ',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white38
                                      : AppColors.textGrey,
                                ),
                              ),
                            if (widget.article.publishedAt.isNotEmpty)
                              Text(
                                _formatDate(widget.article.publishedAt),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white38
                                      : AppColors.textGrey,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Highlighted words section
                      if (widget.article.highlightedWords.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cefrColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cefrColor.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.lightbulb_outline_rounded,
                                    size: 16,
                                    color: cefrColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Vocabulary to learn',
                                    style: TextStyle(
                                      color: cefrColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: widget.article.highlightedWords.map((
                                  word,
                                ) {
                                  return GestureDetector(
                                    onTap: () => _onWordTap(word),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.04,
                                            ),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        word,
                                        style: TextStyle(
                                          color: cefrColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Article body
                      if (_isLoadingFullContent)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: LottieLoadingWidget.tiny(),
                            ),
                          ),
                        ),
                      _buildArticleBody(
                        _fullContent ??
                            (widget.article.content.isNotEmpty
                                ? widget.article.content
                                : widget.article.description),
                        isDark,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Reading Progress Bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: _readingProgress,
                  backgroundColor: Colors.transparent,
                  color: cefrColor,
                  minHeight: 3,
                ),
              ),
            ),
          ),

          // ── Quiz Button (appears at 90% scroll) ──
          if (_showQuizButton)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: _buildQuizButton(cefrColor),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Article Body with Tappable Words
  // ──────────────────────────────────────

  Widget _buildArticleBody(String rawText, bool isDark) {
    if (rawText.isEmpty) {
      return Text(
        'No content available.',
        style: TextStyle(color: isDark ? Colors.white54 : AppColors.textGrey),
      );
    }

    // Decode HTML entities that survive from backend scraping
    final text = _decodeHtmlEntities(rawText);

    final highlightSet = widget.article.highlightedWords
        .map((w) => w.toLowerCase())
        .toSet();

    final cefrColor = _cefrColor(widget.article.cefrLevel);
    final baseStyle = TextStyle(
      fontSize: 16,
      height: 1.7,
      color: isDark ? Colors.white.withValues(alpha: 0.85) : AppColors.textDark,
    );

    // Split into paragraphs
    final paragraphs = text.split(RegExp(r'\n\n|\n'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs.map((paragraph) {
        if (paragraph.trim().isEmpty) return const SizedBox(height: 12);

        // Tokenise into non-space words while keeping track of spacing.
        // Use TextSpan for plain text (preserves whitespace naturally)
        // and WidgetSpan only for highlighted words (tappable + decorated).
        final spans = <InlineSpan>[];
        final tokenRegex = RegExp(r'(\S+)');
        int lastEnd = 0;

        for (final match in tokenRegex.allMatches(paragraph)) {
          // Add any whitespace between the previous token and this one
          if (match.start > lastEnd) {
            spans.add(
              TextSpan(text: paragraph.substring(lastEnd, match.start)),
            );
          }
          lastEnd = match.end;

          final word = match.group(0)!;
          final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
          final isHighlighted =
              cleanWord.isNotEmpty && highlightSet.contains(cleanWord);

          if (isHighlighted) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: () => _onWordTap(
                    word,
                    contextSentence: paragraph,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: cefrColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border(
                        bottom: BorderSide(color: cefrColor, width: 2),
                      ),
                    ),
                    child: Text(
                      word,
                      style: baseStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            );
          } else {
            // Plain text — use TextSpan so whitespace flows naturally
            spans.add(TextSpan(text: word));
          }
        }

        // Trailing whitespace (unlikely, but safe)
        if (lastEnd < paragraph.length) {
          spans.add(TextSpan(text: paragraph.substring(lastEnd)));
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: RichText(
            text: TextSpan(style: baseStyle, children: spans),
          ),
        );
      }).toList(),
    );
  }

  /// Decode common HTML entities that survive from web scraping.
  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&#x27;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&nbsp;', ' ');
  }

  // ──────────────────────────────────────
  //  Quiz Button
  // ──────────────────────────────────────

  Widget _buildQuizButton(Color cefrColor) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        // easeOutBack overshoots above 1.0 — clamp to keep Opacity valid
        final opacity = value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: FilledButton.icon(
        onPressed: () {
          Navigator.pushNamed(context, '/news/quiz', arguments: widget.article);
        },
        icon: const Icon(Icons.quiz_rounded, size: 20),
        label: const Text('Take Comprehension Quiz'),
        style: FilledButton.styleFrom(
          backgroundColor: cefrColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Dictionary Sheet (shared with YouTube)
  // ──────────────────────────────────────

  Widget _buildDictionarySheet(String word, {String? contextSentence}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(widget.article.cefrLevel);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            word,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: cefrColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dictionary lookup will be available in Phase 6.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white54 : AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Future.microtask(() {
                      if (!mounted) return;
                      showQuickSaveWordSheet(
                        context,
                        word: word,
                        sourceType: 'news',
                        sourceReference: widget.article.id.isNotEmpty
                            ? widget.article.id
                            : widget.article.url,
                        contextSentence: contextSentence,
                      );
                    });
                  },
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Save Word'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cefrColor,
                    side: BorderSide(color: cefrColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Close'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cefrColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  Color _cefrColor(String level) {
    switch (level) {
      case 'A1':
        return AppColors.greenSuccessBright;
      case 'A2':
        return AppColors.greenSuccessSoft;
      case 'B1':
        return AppColors.warning;
      case 'B2':
        return AppColors.orange;
      case 'C1':
        return AppColors.deepOrange;
      case 'C2':
        return AppColors.purple;
      default:
        return AppColors.primary;
    }
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
      return '${diff.inDays ~/ 30}mo ago';
    } catch (_) {
      return '';
    }
  }
}
