import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/core/widgets/content_kit.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/premium_gate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/book_entities.dart';
import '../providers/book_provider.dart';
import '../widgets/book_card.dart';
import 'book_quiz_screen.dart';
import 'book_reader_screen.dart';

/// Book detail screen: the cover on a blurred copy of itself, the actions
/// that matter (read, save, download, quiz) and the learner's progress.
///
/// Phase 5: Book Reading — skill: ui-ux-pro-max.
class BookDetailScreen extends StatefulWidget {
  final Book book;

  const BookDetailScreen({super.key, required this.book});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  /// Scroll depth at which the bar turns from clear-over-cover to solid.
  static const _collapseAt = 240.0;

  final _scrollController = ScrollController();
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Provider.openBook() was already called in the library screen
    // Load reader settings so they're ready when we enter the reader
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BookProvider>();
      provider.loadReaderSettings();
      provider.loadSavedBooks();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed = _scrollController.offset > _collapseAt;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;

    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                _Header(book: book),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  child: Consumer<BookProvider>(
                    builder: (context, provider, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Actions(book: book, provider: provider),
                        if (_hasProgress(provider)) ...[
                          const SizedBox(height: 24),
                          _ProgressCard(progress: provider.currentProgress!),
                        ],
                        if (book.description.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            'books.about'.tr(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            book.description,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: contentMuted(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Consumer<BookProvider>(
            builder: (context, provider, _) {
              final saved = provider.isBookSaved(book.id);
              return ContentTopBar(
                title: book.title,
                collapsed: _collapsed,
                actionsBuilder: (iconColor) => [
                  IconButton(
                    onPressed: () => provider.toggleSaveBook(book),
                    tooltip: saved
                        ? 'books.unsaveBook'.tr()
                        : 'books.saveBook'.tr(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(48),
                    ),
                    icon: Icon(
                      saved ? PhosphorIconsFill.heart : PhosphorIconsBold.heart,
                      color: saved
                          ? Theme.of(context).colorScheme.primary
                          : iconColor,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  bool _hasProgress(BookProvider provider) =>
      provider.currentProgress != null &&
      provider.currentProgress!.totalPages > 0;
}

// ──────────────────────────────────────
//  Header
// ──────────────────────────────────────

class _Header extends StatelessWidget {
  final Book book;

  const _Header({required this.book});

  static const _onScrim = Color(0xE6FFFFFF);
  static const _cover = Size(150, 225);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 56;
    final stats = [
      if (book.chapterCount > 0)
        (
          PhosphorIconsBold.listNumbers,
          'books.chapterCountShort'.tr(
            namedArgs: {'count': '${book.chapterCount}'},
          ),
        ),
      if (book.wordCount > 0)
        (
          PhosphorIconsBold.textAa,
          'books.wordCountK'.tr(
            namedArgs: {'count': (book.wordCount / 1000).toStringAsFixed(0)},
          ),
        ),
      (PhosphorIconsBold.translate, book.language.toUpperCase()),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: ContentBackdrop(
            url: book.coverUrl,
            fallback: BookJacket(title: book.title),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, top, 20, 28),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                BookCover(
                  book: book,
                  width: _cover.width,
                  height: _cover.height,
                ),
                const SizedBox(height: 24),
                Text(
                  book.title,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: contentDisplay(context, size: 24, color: Colors.white),
                ),
                if (book.author.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    book.author,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _onScrim, fontSize: 14),
                  ),
                ],
                if (book.subject.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    book.subject,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    CefrBadge(
                      level: book.cefrLevel,
                      size: CefrBadgeSize.medium,
                      onColored: true,
                    ),
                    for (final (icon, label) in stats)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16, color: _onScrim),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: const TextStyle(
                              color: _onScrim,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────
//  Actions
// ──────────────────────────────────────

class _Actions extends StatelessWidget {
  final Book book;
  final BookProvider provider;

  const _Actions({required this.book, required this.provider});

  @override
  Widget build(BuildContext context) {
    final progress = provider.currentProgress;
    final started = progress != null && progress.currentPage > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          icon: const Icon(PhosphorIconsBold.bookOpenText),
          label: Text((started ? 'books.continueCta' : 'books.startCta').tr()),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BookReaderScreen(book: book)),
          ),
        ),
        const SizedBox(height: 12),
        _downloadButton(context),
        if (started) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(PhosphorIconsBold.exam),
            label: Text('books.chapterQuiz'.tr()),
            style: _outlined(context),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const BookQuizScreen(chapter: 1),
              ),
            ),
          ),
        ],
      ],
    );
  }

  ButtonStyle _outlined(BuildContext context) => OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    side: BorderSide(color: Theme.of(context).colorScheme.outline),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
  );

  /// Offline download is a premium perk. An already-downloaded book stays
  /// readable for everyone regardless — only *new* downloads are gated, so
  /// nobody loses access to something they already have on disk.
  Widget _downloadButton(BuildContext context) {
    final isDownloaded = provider.downloadedPath != null;
    final button = OutlinedButton.icon(
      icon: provider.isDownloading
          ? const SizedBox.square(
              dimension: 18,
              child: LottieLoadingWidget.tiny(),
            )
          : Icon(
              isDownloaded
                  ? PhosphorIconsFill.checkCircle
                  : PhosphorIconsBold.downloadSimple,
            ),
      label: Text(
        provider.isDownloading
            ? 'books.downloading'.tr()
            : isDownloaded
            ? 'books.downloaded'.tr()
            : 'books.download'.tr(),
      ),
      style: _outlined(context),
      onPressed: provider.isDownloading || isDownloaded
          ? null
          : provider.downloadBook,
    );
    return isDownloaded ? button : PremiumGate(child: button);
  }
}

// ──────────────────────────────────────
//  Reading progress
// ──────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  final UserBook progress;

  const _ProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (progress.readingProgress * 100).round().clamp(0, 100);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'books.readingProgress'.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.readingProgress.clamp(0.0, 1.0),
                minHeight: 6,
                color: scheme.primary,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'books.pageProgress'.tr(
                namedArgs: {
                  'current': '${progress.currentPage + 1}',
                  'total': '${progress.totalPages}',
                },
              ),
              style: TextStyle(fontSize: 12, color: contentMuted(context)),
            ),
          ],
        ),
      ),
    );
  }
}
