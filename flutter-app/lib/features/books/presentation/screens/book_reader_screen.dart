import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/known_words_service.dart';
import '../../../../core/services/dictionary_service.dart';
import '../../../../core/services/quick_save_vocabulary_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/book_entities.dart';
import '../providers/book_provider.dart';
import '../widgets/bookmark_button.dart';
import '../widgets/reader_controls.dart';
import 'book_quiz_screen.dart';
import 'package:lexilingo_app/core/services/content_time_tracker.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Paginated plain-text reader with font controls, theme, bookmarks, and XP.
///
/// Phase 5: Book Reading — skill: ui-ux-pro-max, srs-sm2-algorithm.
class BookReaderScreen extends StatefulWidget {
  final Book book;

  const BookReaderScreen({super.key, required this.book});

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  final PageController _pageController = PageController();

  /// Time with the book open is practice, credited in idempotent chunks and
  /// only while the learner is actually turning pages.
  late final ContentTimeTracker _readingTime;

  bool _isCurrentPageBookmarked = false;
  bool _showControls = true;
  final Set<int> _dismissedQuizSections = {};

  @override
  void initState() {
    super.initState();
    _readingTime = ContentTimeTracker(
      source: 'book',
      sourceIdPrefix: 'read:${widget.book.id}',
      sourceDetail: 'reading_time',
    )..start();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<BookProvider>();
      await provider.loadBookText();
      if (!mounted) return;
      // The PageView only exists once the loaded pages have been built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (provider.currentPage > 0 && _pageController.hasClients) {
          _pageController.jumpToPage(provider.currentPage);
        }
      });
      _refreshBookmarkState();
    });
  }

  @override
  void dispose() {
    _readingTime.stop();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshBookmarkState() async {
    final marked = await context.read<BookProvider>().isCurrentPageBookmarked();
    if (mounted) setState(() => _isCurrentPageBookmarked = marked);
  }

  Future<void> _onPageChanged(int page) async {
    // Turning a page is the proof someone is reading.
    _readingTime.markActive();
    await context.read<BookProvider>().goToPage(page);
    if (!mounted) return;
    _refreshBookmarkState();
  }

  void _toggleControls() {
    _readingTime.markActive();
    setState(() => _showControls = !_showControls);
  }

  void _showReaderControls() {
    final provider = context.read<BookProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => ReaderControls(
          settings: provider.readerSettings,
          onChanged: (updated) {
            setModalState(() {});
            provider.updateReaderSettings(updated);
          },
        ),
      ),
    );
  }

  void _showBookmarksPanel() {
    final provider = context.read<BookProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.readingNight
          : AppColors.onGradient,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        if (provider.bookmarks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Center(
              child: Text(
                'bookReader.noBookmarksYet'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            Text(
              'bookReader.bookmarks'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            ...provider.bookmarks.map(
              (b) => ListTile(
                leading: Icon(
                  Icons.bookmark_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  'bookReader.bookmarkPage'.tr(
                    namedArgs: {'page': '${b.page + 1}'},
                  ),
                ),
                subtitle: b.note.isNotEmpty ? Text(b.note) : null,
                onTap: () {
                  Navigator.pop(context);
                  _pageController.jumpToPage(b.page);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showWordDefinition(String word) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark
        ? AppColors.surfaceDarkElevated
        : AppColors.onGradient;
    final textColor = isDark
        ? AppColors.onGradient
        : Theme.of(context).colorScheme.onSurface;
    final subtextColor = isDark
        ? Colors.white54
        : Theme.of(context).colorScheme.onSurfaceVariant;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DictionarySheet(
        word: word,
        sourceReference: widget.book.id,
        sheetBg: sheetBg,
        textColor: textColor,
        subtextColor: subtextColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BookProvider>(
      builder: (context, provider, _) {
        final settings = provider.readerSettings;
        final bgColor = _readerBg(settings.theme);
        final textColor = _readerText(settings.theme);

        return Scaffold(
          backgroundColor: bgColor,
          body: ContentWidth(
            maxWidth: ContentWidth.reading,
            child: Stack(
              children: [
                // ── Content ────────────────────────────────────
                if (provider.isLoading)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const LottieLoadingWidget.medium(),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'bookReader.loadingBook'.tr(),
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (provider.error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'bookReader.couldNotLoad'.tr() +
                                (provider.error != null
                                    ? '\n${provider.error}'
                                    : ''),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton(
                            onPressed: () => provider.loadBookText(),
                            child: Text('bookReader.retry'.tr()),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (provider.pages.isNotEmpty)
                  GestureDetector(
                    onTap: _toggleControls,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (_) {
                        _readingTime.markActive();
                        return false;
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: provider.pages.length,
                        itemBuilder: (context, pageIndex) {
                          return _buildPage(
                            context,
                            provider.pages[pageIndex],
                            settings,
                            textColor,
                            bgColor,
                          );
                        },
                      ),
                    ),
                  ),

                // ── Top bar (show/hide on tap) ──────────────────
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  top: _showControls
                      ? 0
                      : -(MediaQuery.of(context).padding.top + 60),
                  left: 0,
                  right: 0,
                  child: _buildTopBar(context, provider, settings, textColor),
                ),

                // ── Section quiz offer ─────────────────────────
                if (_quizOffer(provider) case final section?)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    bottom:
                        MediaQuery.of(context).padding.bottom +
                        (_showControls ? 88 : AppSpacing.lg),
                    child: _SectionQuizBanner(
                      section: section,
                      onStart: () {
                        _readingTime.markActive();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BookQuizScreen(section: section),
                          ),
                        );
                      },
                      onDismiss: () =>
                          setState(() => _dismissedQuizSections.add(section)),
                    ),
                  ),

                // ── Bottom bar ─────────────────────────────────
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  bottom: _showControls ? 0 : -80,
                  left: 0,
                  right: 0,
                  child: _buildBottomBar(
                    context,
                    provider,
                    settings,
                    textColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The section whose quiz was just unlocked by reaching this page, if the
  /// learner has not finished or dismissed it.
  int? _quizOffer(BookProvider provider) {
    if (provider.isLoading || provider.pages.isEmpty) return null;
    final access = provider.quizAccess;
    final section = access.section;
    if (access.kind != QuizAccessKind.take || section == null) return null;
    if (_dismissedQuizSections.contains(section)) return null;
    final unlock = QuizSections.unlockPage(section, provider.totalPages);
    final page = provider.currentPage;
    return page >= unlock && page <= unlock + 1 ? section : null;
  }

  Widget _buildPage(
    BuildContext context,
    String pageText,
    ReaderSettings settings,
    Color textColor,
    Color bgColor,
  ) {
    final matches = RegExp(r'(\s+|[^\s]+)').allMatches(pageText);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 68,
        20,
        100,
      ),
      child: RichText(
        text: TextSpan(
          children: matches.map((match) {
            final val = match.group(0)!;
            final isWhitespace = RegExp(r'\s').hasMatch(val);
            if (isWhitespace) {
              return TextSpan(
                text: val,
                style: TextStyle(
                  fontSize: settings.fontSize,
                  height: settings.lineSpacing,
                  color: textColor,
                ),
              );
            }

            final clean = val.replaceAll(RegExp(r'[^\w]'), '');
            if (clean.isEmpty) {
              return TextSpan(
                text: val,
                style: TextStyle(
                  fontSize: settings.fontSize,
                  height: settings.lineSpacing,
                  color: textColor,
                ),
              );
            }

            return WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onLongPress: clean.length > 2
                    ? () => _showWordDefinition(clean)
                    : null,
                child: Text(
                  val,
                  style: TextStyle(
                    fontSize: settings.fontSize,
                    height: settings.lineSpacing,
                    color: textColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    BookProvider provider,
    ReaderSettings settings,
    Color textColor,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        4,
        MediaQuery.of(context).padding.top + 4,
        4,
        4,
      ),
      decoration: BoxDecoration(
        color: _readerBg(settings.theme).withValues(alpha: 0.95),
      ),
      child: Row(
        children: [
          AppBackButton(
            icon: Icons.arrow_back_rounded,
            color: textColor,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          BookmarkButton(
            isBookmarked: _isCurrentPageBookmarked,
            onToggle: () async {
              await provider.toggleBookmark();
              if (!mounted) return;
              _refreshBookmarkState();
            },
          ),
          IconButton(
            icon: Icon(Icons.bookmarks_rounded, color: textColor),
            onPressed: _showBookmarksPanel,
            tooltip: 'bookReader.allBookmarks'.tr(),
          ),
          IconButton(
            icon: Icon(Icons.text_format_rounded, color: textColor),
            onPressed: _showReaderControls,
            tooltip: 'bookReader.readerSettings'.tr(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    BookProvider provider,
    ReaderSettings settings,
    Color textColor,
  ) {
    final totalPages = provider.totalPages;
    final cur = provider.currentPage;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: _readerBg(settings.theme).withValues(alpha: 0.95),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          if (totalPages > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: totalPages > 1 ? cur / (totalPages - 1) : 1.0,
                minHeight: 3,
                backgroundColor: textColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),

          // Page counter + navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: cur > 0
                    ? () => _pageController.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      )
                    : null,
                icon: Icon(Icons.navigate_before_rounded, color: textColor),
              ),
              Expanded(
                child: Text(
                  totalPages > 0
                      ? 'bookReader.page'.tr(
                          namedArgs: {
                            'current': '${cur + 1}',
                            'total': '$totalPages',
                          },
                        )
                      : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
              IconButton(
                onPressed: cur < totalPages - 1
                    ? () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      )
                    : null,
                icon: Icon(Icons.navigate_next_rounded, color: textColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _readerBg(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return AppColors.readingPaper;
      case ReaderTheme.sepia:
        return AppColors.readingSepia;
      case ReaderTheme.dark:
        return AppColors.readingNight;
    }
  }

  Color _readerText(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return Colors.black87;
      case ReaderTheme.sepia:
        return AppColors.readingSepiaText;
      case ReaderTheme.dark:
        return AppColors.readingNightAlt;
    }
  }
}

/// Slim, non-blocking prompt shown when a section's quiz unlocks.
class _SectionQuizBanner extends StatelessWidget {
  const _SectionQuizBanner({
    required this.section,
    required this.onStart,
    required this.onDismiss,
  });

  final int section;
  final VoidCallback onStart;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'books.sectionQuizReady'.tr(namedArgs: {'section': '$section'}),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text('books.startQuiz'.tr()),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: 'common.close'.tr(),
              style: IconButton.styleFrom(minimumSize: const Size.square(44)),
              icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet widget that asynchronously looks up a word definition.
class _DictionarySheet extends StatefulWidget {
  final String word;
  final String? sourceReference;
  final Color sheetBg;
  final Color textColor;
  final Color subtextColor;

  const _DictionarySheet({
    required this.word,
    this.sourceReference,
    required this.sheetBg,
    required this.textColor,
    required this.subtextColor,
  });

  @override
  State<_DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<_DictionarySheet> {
  WordDefinition? _definition;
  bool _loading = true;
  bool _isSaving = false;
  bool _notFound = false;
  bool _isAlreadySaved = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    _checkAlreadySaved();
  }

  /// Without this, a word saved in a previous reading session always shows
  /// the plain "Save" button again — the sheet had no way to know the
  /// backend already has it.
  Future<void> _checkAlreadySaved() async {
    final known = await sl<KnownWordsService>().getKnownWords();
    if (!mounted) return;
    if (known.contains(widget.word.trim().toLowerCase())) {
      setState(() => _isAlreadySaved = true);
    }
  }

  Future<void> _fetch() async {
    final result = await sl<DictionaryService>().lookup(widget.word);
    if (!mounted) return;
    setState(() {
      _definition = result;
      _loading = false;
      _notFound = result == null;
    });
  }

  Future<void> _saveWord() async {
    if (_isSaving || _isAlreadySaved) return;

    setState(() => _isSaving = true);
    try {
      final result = await sl<QuickSaveVocabularyService>().quickSaveWord(
        word: widget.word,
        sourceType: 'book',
        sourceReference: widget.sourceReference,
      );

      if (!mounted) return;
      setState(() => _isAlreadySaved = true);
      final message = result.alreadyInCollection && result.reviewScheduled
          ? 'vocabulary.resavedForReview'.tr()
          : result.alreadyInCollection
          ? 'bookReader.wordAlreadyInCollection'.tr(
              namedArgs: {'word': result.normalizedWord},
            )
          : 'bookReader.wordSaved'.tr(
              namedArgs: {'word': result.normalizedWord},
            );

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.status.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('bookReader.couldNotSaveWord'.tr()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: widget.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Content
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const LottieLoadingWidget.tiny(),
                          const SizedBox(height: 10),
                          Text(
                            'bookReader.lookingUp'.tr(
                              namedArgs: {'word': widget.word},
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: widget.subtextColor),
                          ),
                        ],
                      ),
                    )
                  : _notFound
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          'bookReader.noDefinitionFound'.tr(
                            namedArgs: {'word': widget.word},
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: widget.subtextColor),
                        ),
                      ),
                    )
                  : _buildDefinitionContent(controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefinitionContent(ScrollController controller) {
    final def = _definition!;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.xxl),
      children: [
        // Word + phonetic
        Text(
          def.word,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: widget.textColor,
          ),
        ),
        if (def.phonetic != null) ...[
          const SizedBox(height: 2),
          Text(
            def.phonetic!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_isSaving || _isAlreadySaved) ? null : _saveWord,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: LottieLoadingWidget.tiny(),
                  )
                : Icon(
                    _isAlreadySaved
                        ? Icons.check_circle_rounded
                        : Icons.bookmark_add_outlined,
                    size: 18,
                  ),
            label: Text(
              _isAlreadySaved
                  ? 'bookReader.wordAlreadySavedButton'.tr()
                  : 'bookReader.saveWordToVocabulary'.tr(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Meanings
        ...def.meanings.map((m) => _buildMeaning(m)),
      ],
    );
  }

  Widget _buildMeaning(MeaningEntry m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Part of speech chip
        Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            m.partOfSpeech,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // Definitions
        ...m.definitions.asMap().entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.key + 1}.  ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: widget.subtextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Text(
                    e.value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: widget.textColor,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Examples
        ...m.examples.map(
          (ex) => Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              '"$ex"',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.subtextColor,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ),
        // Synonyms
        if (m.synonyms.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: m.synonyms
                .map(
                  (s) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      s,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: widget.subtextColor,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
