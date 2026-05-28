import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/book_entities.dart';
import '../providers/book_provider.dart';
import '../widgets/book_card.dart';
import 'book_detail_screen.dart';

/// Library screen showing curated books by CEFR level + global search.
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

  @override
  void initState() {
    super.initState();
    for (final level in _cefrLevels) {
      final sc = ScrollController();
      sc.addListener(() => _onLevelScroll(level, sc));
      _scrollControllers[level] = sc;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookProvider>().loadRecommendedBooks();
      context.read<BookProvider>().loadSavedBooks();
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

  void _openBook(BuildContext context, Book book) async {
    final provider = context.read<BookProvider>();
    await provider.openBook(book);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'books.library'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isSearchMode ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() {
                _isSearchMode = !_isSearchMode;
                if (!_isSearchMode) {
                  _searchController.clear();
                  context.read<BookProvider>().clearSearch();
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          if (_isSearchMode) _buildSearchBar(context, isDark),

          Expanded(
            child: _isSearchMode
                ? _buildSearchResults(context, isDark)
                : _buildLibrary(context, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'books.searchPlaceholder'.tr(),
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: isDark ? AppColors.surfaceDarkElevated : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (q) => context.read<BookProvider>().searchBooks(q),
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context, bool isDark) {
    return Consumer<BookProvider>(
      builder: (context, provider, _) {
        if (provider.isSearching) {
          return const Center(child: LottieLoadingWidget.medium());
        }
        if (provider.searchResults.isEmpty &&
            _searchController.text.length >= 2) {
          return Center(
            child: Text(
              'books.noBooksFound'.tr(
                namedArgs: {'query': _searchController.text},
              ),
              style: TextStyle(
                color: isDark ? Colors.white54 : AppColors.textGrey,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: provider.searchResults.length,
          itemBuilder: (context, i) => _buildSearchResultTile(
            context,
            provider.searchResults[i],
            isDark,
          ),
        );
      },
    );
  }

  Widget _buildSearchResultTile(BuildContext context, Book book, bool isDark) {
    final cefrColor = _cefrColor(book.cefrLevel);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: book.coverUrl.isNotEmpty
              ? Image.network(
                  book.coverUrl,
                  width: 48,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallbackCoverSmall(cefrColor),
                )
              : _fallbackCoverSmall(cefrColor),
        ),
        title: Text(
          book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(
              book.author,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : AppColors.textGrey,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cefrColor,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                book.cefrLevel,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.surface,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        onTap: () => _openBook(context, book),
      ),
    );
  }

  Widget _fallbackCoverSmall(Color cefrColor) => Container(
    width: 48,
    height: 64,
    decoration: BoxDecoration(
      color: cefrColor.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(Icons.menu_book_rounded, size: 24, color: cefrColor),
  );

  Widget _buildLibrary(BuildContext context, bool isDark) {
    return Consumer<BookProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.textGrey,
                ),
                const SizedBox(height: 12),
                Text(
                  'books.loadError'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    provider.error!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white38
                          : AppColors.textGrey.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => provider.loadRecommendedBooks(),
                  child: Text('common.retry'.tr()),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadRecommendedBooks(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Saved books section
              if (provider.savedBooks.isNotEmpty) ...[
                _buildSavedSection(context, provider, isDark),
                const SizedBox(height: 20),
              ],

              // Topic / genre filter chips
              _buildTopicFilterRow(context, provider, isDark),
              const SizedBox(height: 20),

              // Sections by CEFR level
              ..._cefrLevels.map(
                (level) => _buildLevelSection(context, level, provider, isDark),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSavedSection(
    BuildContext context,
    BookProvider provider,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.favorite_rounded, color: Colors.red, size: 18),
            const SizedBox(width: 6),
            Text(
              'books.savedBooks'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${provider.savedBooks.length}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: provider.savedBooks.length,
            itemBuilder: (context, i) {
              final book = provider.savedBooks[i];
              return BookCard(
                book: book,
                onTap: () => _openBook(context, book),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTopicFilterRow(
    BuildContext context,
    BookProvider provider,
    bool isDark,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _topicChip(context, provider, isDark, null, 'All'),
          ...BookProvider.kTopics.map(
            (t) => _topicChip(context, provider, isDark, t, t),
          ),
        ],
      ),
    );
  }

  Widget _topicChip(
    BuildContext context,
    BookProvider provider,
    bool isDark,
    String? topic,
    String label,
  ) {
    final isSelected = provider.selectedTopic == topic;
    return GestureDetector(
      onTap: () => provider.setTopicFilter(topic),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : isDark
              ? AppColors.surfaceDarkElevated
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.grey300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : isDark
                ? Colors.white60
                : AppColors.textGrey,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildLevelSection(
    BuildContext context,
    String level,
    BookProvider provider,
    bool isDark,
  ) {
    final books = provider.booksForLevel(level);
    final isLoadingMore = provider.isLoadingMoreForLevel(level);
    if (books.isEmpty && !isLoadingMore) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _cefrColor(level),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                level,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.surface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _cefrLabel(level),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : AppColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 264,
          child: ListView.builder(
            controller: _scrollControllers[level],
            scrollDirection: Axis.horizontal,
            itemCount: books.length + (isLoadingMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == books.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return BookCard(
                book: books[i],
                onTap: () => _openBook(context, books[i]),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
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

  String _cefrLabel(String level) {
    const map = {
      'A1': 'Beginner',
      'A2': 'Elementary',
      'B1': 'Intermediate',
      'B2': 'Upper Intermediate',
      'C1': 'Advanced',
      'C2': 'Proficiency',
    };
    return map[level] ?? level;
  }
}
