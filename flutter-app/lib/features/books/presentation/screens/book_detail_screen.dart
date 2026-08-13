import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/book_entities.dart';
import '../providers/book_provider.dart';
import 'book_quiz_screen.dart';
import 'book_reader_screen.dart';

/// Book detail screen showing cover, synopsis, CEFR badge, and Read/Download actions.
///
/// Phase 5: Book Reading — skill: ui-ux-pro-max.
class BookDetailScreen extends StatefulWidget {
  final Book book;

  const BookDetailScreen({super.key, required this.book});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Provider.openBook() was already called in the library screen
    // Load reader settings so they're ready when we enter the reader
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BookProvider>();
      provider.loadReaderSettings();
      provider.loadSavedBooks();
    });
  }

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final book = widget.book;
    final cefrColor = _cefrColor(book.cefrLevel);

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: CustomScrollView(
        slivers: [
          // Hero app bar with cover
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: isDark
                ? AppColors.backgroundDark
                : AppColors.backgroundLight,
            leading: AppBackButton(
              icon: Icons.arrow_back_rounded,
              color: Theme.of(context).colorScheme.surface,
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Consumer<BookProvider>(
                builder: (context, provider, _) {
                  final isSaved = provider.isBookSaved(book.id);
                  return IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSaved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isSaved ? Colors.red : Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: () => provider.toggleSaveBook(book),
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Background image (blurred)
                  if (book.coverUrl.isNotEmpty)
                    Image.network(
                      book.coverUrl,
                      fit: BoxFit.cover,
                      color: Colors.black.withValues(alpha: 0.5),
                      colorBlendMode: BlendMode.darken,
                      errorBuilder: (_, __, ___) =>
                          Container(color: cefrColor.withValues(alpha: 0.4)),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cefrColor.withValues(alpha: 0.7),
                            cefrColor.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                    ),
                  // Centered book cover
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: book.coverUrl.isNotEmpty
                          ? Image.network(
                              book.coverUrl,
                              width: 120,
                              height: 180,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildFallback(cefrColor),
                            )
                          : _buildFallback(cefrColor),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + CEFR chip
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textDark,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: cefrColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          book.cefrLevel,
                          style: TextStyle(
                            color: AppColors.surfaceLight,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Author
                  Text(
                    book.author,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white60 : AppColors.textGrey,
                    ),
                  ),
                  if (book.subject.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      book.subject,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white38 : AppColors.textGrey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Stats row
                  _buildStatRow(isDark, book),
                  const SizedBox(height: 20),

                  // Description
                  if (book.description.isNotEmpty) ...[
                    Text(
                      'books.about'.tr(),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.description,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: isDark ? Colors.white70 : AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Reading progress
                  Consumer<BookProvider>(
                    builder: (context, provider, _) {
                      final progress = provider.currentProgress;
                      if (progress == null || progress.totalPages == 0) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'books.readingProgress'.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white70
                                      : AppColors.textDark,
                                ),
                              ),
                              Text(
                                '${(progress.readingProgress * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cefrColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress.readingProgress,
                              minHeight: 6,
                              backgroundColor: isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : AppColors.grey200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                cefrColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'books.pageProgress'.tr(
                              namedArgs: {
                                'current': '${progress.currentPage + 1}',
                                'total': '${progress.totalPages}',
                              },
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white38
                                  : AppColors.textGrey,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),

                  // Actions
                  Consumer<BookProvider>(
                    builder: (context, provider, _) {
                      final isDownloaded = provider.downloadedPath != null;
                      return Column(
                        children: [
                          // Read button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.menu_book_rounded),
                              label: Text(
                                provider.currentProgress != null &&
                                        provider.currentProgress!.currentPage >
                                            0
                                    ? 'Continue Reading'
                                    : 'Start Reading',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        BookReaderScreen(book: book),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Download button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: provider.isDownloading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: LottieLoadingWidget.tiny(),
                                    )
                                  : Icon(
                                      isDownloaded
                                          ? Icons.download_done_rounded
                                          : Icons.download_rounded,
                                    ),
                              label: Text(
                                provider.isDownloading
                                    ? 'Downloading...'
                                    : isDownloaded
                                    ? 'Downloaded'
                                    : 'Download for Offline',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDownloaded
                                    ? AppColors.greenSuccess
                                    : AppColors.primary,
                                side: BorderSide(
                                  color: isDownloaded
                                      ? AppColors.greenSuccess
                                      : AppColors.primary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: provider.isDownloading || isDownloaded
                                  ? null
                                  : () => provider.downloadBook(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Chapter Quiz button — show when user has started reading
                          if (provider.currentProgress != null &&
                              provider.currentProgress!.currentPage > 0)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.quiz_rounded),
                                label: Text('books.chapterQuiz'.tr()),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.purple,
                                  side: const BorderSide(
                                    color: AppColors.purple,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const BookQuizScreen(chapter: 1),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(bool isDark, Book book) {
    final stats = [
      if (book.chapterCount > 0)
        _StatItem(
          icon: Icons.format_list_numbered_rounded,
          label: 'books.chapterCountShort'.tr(namedArgs: {'count': '${book.chapterCount}'}),
          isDark: isDark,
        ),
      if (book.wordCount > 0)
        _StatItem(
          icon: Icons.text_fields_rounded,
          label: 'books.wordCountK'.tr(namedArgs: {'count': (book.wordCount / 1000).toStringAsFixed(0)}),
          isDark: isDark,
        ),
      _StatItem(
        icon: Icons.language_rounded,
        label: book.language.toUpperCase(),
        isDark: isDark,
      ),
    ];

    if (stats.isEmpty) return const SizedBox.shrink();

    return Row(
      children: stats
          .expand((s) => [s, const SizedBox(width: 16)])
          .take(stats.length * 2 - 1)
          .toList(),
    );
  }

  Widget _buildFallback(Color cefrColor) => Container(
    width: 120,
    height: 180,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          cefrColor.withValues(alpha: 0.8),
          cefrColor.withValues(alpha: 0.4),
        ],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.menu_book_rounded,
        size: 48,
        color: AppColors.surfaceLight,
      ),
    ),
  );
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white54 : AppColors.textGrey,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white54 : AppColors.textGrey,
          ),
        ),
      ],
    );
  }
}
