import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/core/widgets/content_kit.dart';
import 'package:lexilingo_app/core/widgets/empty_state_widget.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/book_entities.dart';
import '../providers/book_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/book_hero.dart';
import 'book_detail_screen.dart';
import 'book_reader_screen.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Library screen: a hero for what to read next, then curated shelves by CEFR
/// level, with global search.
///
/// Phase 5: Book Reading — skill: ui-ux-pro-max.
class BookLibraryScreen extends StatefulWidget {
  const BookLibraryScreen({super.key});

  @override
  State<BookLibraryScreen> createState() => _BookLibraryScreenState();
}

class _BookLibraryScreenState extends State<BookLibraryScreen> {
  final _searchController = TextEditingController();
  bool _isSearchMode = false;
  final Map<String, ScrollController> _scrollControllers = {};

  static const _cefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
  static const _maxHero = 4;

  @override
  void initState() {
    super.initState();
    for (final level in _cefrLevels) {
      final sc = ScrollController();
      sc.addListener(() => _onLevelScroll(level, sc));
      _scrollControllers[level] = sc;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BookProvider>();
      provider.loadRecommendedBooks();
      provider.loadSavedBooks();
      provider.loadContinueReading();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final sc in _scrollControllers.values) {
      sc.dispose();
    }
    super.dispose();
  }

  void _onLevelScroll(String level, ScrollController sc) {
    if (!sc.hasClients) return;
    if (sc.position.pixels >= sc.position.maxScrollExtent * 0.75) {
      context.read<BookProvider>().loadMoreForLevel(level);
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchMode = !_isSearchMode;
      if (!_isSearchMode) {
        _searchController.clear();
        context.read<BookProvider>().clearSearch();
      }
    });
  }

  Future<void> _refresh() async {
    final provider = context.read<BookProvider>();
    await Future.wait([
      provider.loadRecommendedBooks(),
      provider.loadContinueReading(),
    ]);
  }

  void _refreshShelves() {
    if (!mounted) return;
    final provider = context.read<BookProvider>();
    provider.loadContinueReading();
    provider.loadSavedBooks();
  }

  /// False when the book's progress could not be loaded; the learner is told
  /// and can retry instead of landing on an empty detail screen.
  Future<bool> _prepare(Book book) async {
    final provider = context.read<BookProvider>();
    await provider.openBook(book);
    if (!mounted) return false;
    if (provider.currentBook?.id != book.id || !provider.openFailed) {
      return provider.currentBook?.id == book.id;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('bookReader.couldNotLoad'.tr()),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'common.retry'.tr(),
            onPressed: () => _openBook(book),
          ),
        ),
      );
    return false;
  }

  Future<void> _openBook(Book book) async {
    if (!await _prepare(book) || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
    );
    _refreshShelves();
  }

  /// Straight back into the reader, at the saved page.
  Future<void> _continue(Book book) async {
    if (!await _prepare(book) || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookReaderScreen(book: book)),
    );
    _refreshShelves();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<BookProvider>(
          builder: (context, provider, _) => RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context)),
                if (_isSearchMode)
                  SliverToBoxAdapter(child: _buildSearchField(context)),
                ..._isSearchMode
                    ? _buildSearchResults(provider)
                    : _buildLibrary(context, provider),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          AppBackButton(onPressed: () => Navigator.pop(context)),
          Expanded(
            child: Text(
              'books.library'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: contentDisplay(context),
            ),
          ),
          IconButton(
            onPressed: _toggleSearch,
            tooltip: MaterialLocalizations.of(context).searchFieldLabel,
            style: IconButton.styleFrom(minimumSize: const Size.square(48)),
            icon: Icon(
              _isSearchMode
                  ? PhosphorIconsBold.x
                  : PhosphorIconsBold.magnifyingGlass,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = contentMuted(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.xs, 20, AppSpacing.lg),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: (q) {
          setState(() {});
          context.read<BookProvider>().searchBooks(q);
        },
        decoration: InputDecoration(
          hintText: 'books.searchPlaceholder'.tr(),
          hintStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: muted),
          prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, color: muted),
          filled: true,
          fillColor: scheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Search results
  // ──────────────────────────────────────

  List<Widget> _buildSearchResults(BookProvider provider) {
    if (provider.isSearching) {
      return const [
        // Not hasScrollBody:false — that asks the child for its intrinsic
        // height, and LottieLoadingWidget's LayoutBuilder cannot answer.
        SliverFillRemaining(child: Center(child: LottieLoadingWidget.medium())),
      ];
    }
    if (provider.searchResults.isEmpty) {
      if (_searchController.text.length < 2) return const [];
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: PhosphorIconsBold.books,
            iconSize: 48,
            title: 'books.noBooksFound'.tr(
              namedArgs: {'query': _searchController.text},
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        sliver: SliverList.separated(
          itemCount: provider.searchResults.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) => _SearchResultTile(
            book: provider.searchResults[i],
            onTap: () => _openBook(provider.searchResults[i]),
          ),
        ),
      ),
    ];
  }

  // ──────────────────────────────────────
  //  Library
  // ──────────────────────────────────────

  List<Widget> _buildLibrary(BuildContext context, BookProvider provider) {
    final hasBooks = provider.recommendedBooks.isNotEmpty;

    if (provider.isLoading && !hasBooks) {
      return const [
        SliverFillRemaining(child: Center(child: LottieLoadingWidget.medium())),
      ];
    }
    if (provider.error != null && !hasBooks) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: PhosphorIconsBold.wifiSlash,
            iconSize: 48,
            title: 'books.loadError'.tr(),
            actionLabel: 'common.retry'.tr(),
            onAction: () {
              provider.clearError();
              provider.loadRecommendedBooks();
            },
          ),
        ),
      ];
    }

    final hero = _heroItems(provider);
    final topics = [
      'books.filterAll'.tr(),
      ...BookProvider.kTopics.map(_topicLabel),
    ];
    final topicIndex = provider.selectedTopic == null
        ? 0
        : BookProvider.kTopics.indexOf(provider.selectedTopic!) + 1;

    return [
      if (hero.isNotEmpty)
        SliverToBoxAdapter(
          child: ContentCarousel(
            count: hero.length,
            height: ContentHero.heightOf(context),
            itemBuilder: (context, i) {
              final item = hero[i];
              return BookHero(
                book: item.book,
                entry: item.entry,
                onTap: () => item.entry != null
                    ? _continue(item.book)
                    : _openBook(item.book),
              );
            },
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: ContentChipBar(
            labels: topics,
            selected: topicIndex,
            onSelected: (i) => provider.setTopicFilter(
              i == 0 ? null : BookProvider.kTopics[i - 1],
            ),
          ),
        ),
      ),
      if (provider.savedBooks.isNotEmpty)
        ..._shelf(
          title: '${'books.savedBooks'.tr()} · ${provider.savedBooks.length}',
          books: provider.savedBooks,
        ),
      for (final level in _cefrLevels) ..._levelShelf(level, provider),
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ];
  }

  /// What the carousel leads with: books in progress, else a few covers worth
  /// opening (the first curated ones that have artwork).
  List<({Book book, ReadingEntry? entry})> _heroItems(BookProvider provider) {
    final reading = provider.continueReading;
    if (reading.isNotEmpty) {
      return [for (final e in reading.take(_maxHero)) (book: e.book, entry: e)];
    }
    return [
      for (final b
          in provider.recommendedBooks
              .where((b) => b.coverUrl.isNotEmpty)
              .take(_maxHero))
        (book: b, entry: null),
    ];
  }

  List<Widget> _shelf({
    required String title,
    required List<Book> books,
    ScrollController? controller,
    bool loadingMore = false,
  }) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xl,
            bottom: AppSpacing.md,
          ),
          child: ContentSectionHeader(title: title),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: BookCard.rowHeight(context),
          child: ListView.separated(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: books.length + (loadingMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
            itemBuilder: (context, i) {
              if (i == books.length) {
                return const Center(child: LottieLoadingWidget.tiny());
              }
              return BookCard(book: books[i], onTap: () => _openBook(books[i]));
            },
          ),
        ),
      ),
    ];
  }

  List<Widget> _levelShelf(String level, BookProvider provider) {
    final books = provider.booksForLevel(level);
    final loadingMore = provider.isLoadingMoreForLevel(level);
    if (books.isEmpty && !loadingMore) return const [];
    return _shelf(
      title: '$level · ${_levelLabel(level)}',
      books: books,
      controller: _scrollControllers[level],
      loadingMore: loadingMore,
    );
  }

  String _levelLabel(String level) => switch (level) {
    'A1' => 'course.difficulty.beginner'.tr(),
    'A2' => 'course.difficulty.elementary'.tr(),
    'B1' => 'course.difficulty.intermediate'.tr(),
    'B2' => 'course.difficulty.upperIntermediate'.tr(),
    'C1' => 'course.difficulty.advanced'.tr(),
    'C2' => 'books.levelProficiency'.tr(),
    _ => level,
  };
}

// ──────────────────────────────────────
//  Search result tile
// ──────────────────────────────────────

class _SearchResultTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;

  const _SearchResultTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: SizedBox(
                        width: 56,
                        height: 84,
                        child: book.coverUrl.isEmpty
                            ? BookJacket(title: book.title)
                            : ContentImage(
                                url: book.coverUrl,
                                fallbackIcon: PhosphorIconsBold.bookOpenText,
                              ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            book.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: contentMuted(context)),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          CefrBadge(
                            level: book.cefrLevel,
                            size: CefrBadgeSize.small,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      PhosphorIconsBold.caretRight,
                      size: 16,
                      color: contentMuted(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Genres stay English in the provider: they are the catalogue's query terms.
String _topicLabel(String topic) {
  final words = topic.toLowerCase().split(' ');
  final id =
      words.first +
      words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
  final key = 'books.topic.$id';
  final translated = key.tr();
  return translated == key ? topic : translated;
}
