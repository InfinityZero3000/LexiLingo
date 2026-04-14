import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/book_entities.dart';
import '../providers/book_provider.dart';
import '../widgets/book_card.dart';
import 'book_detail_screen.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

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

  static const _cefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookProvider>().loadRecommendedBooks();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        title: const Text(
          'Book Library',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
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
          hintText: 'Search books by title or author...',
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
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.searchResults.isEmpty &&
            _searchController.text.length >= 2) {
          return Center(
            child: Text(
              'No books found for "${_searchController.text}"',
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
          return const Center(child: CircularProgressIndicator());
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
                  'Could not load books.\nPlease try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => provider.loadRecommendedBooks(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadRecommendedBooks(
            cefrLevel: provider.selectedCefrLevel,
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // CEFR level filter chips
              _buildCefrFilterRow(context, provider, isDark),
              const SizedBox(height: 20),

              // Section: All Levels
              if (provider.selectedCefrLevel == null) ...[
                ..._cefrLevels
                    .where(
                      (level) => provider.recommendedBooks.any(
                        (b) => b.cefrLevel == level,
                      ),
                    )
                    .map(
                      (level) => _buildLevelSection(
                        context,
                        level,
                        provider.recommendedBooks
                            .where((b) => b.cefrLevel == level)
                            .toList(),
                        isDark,
                      ),
                    ),
              ] else ...[
                _buildBookGrid(context, provider.recommendedBooks, isDark),
              ],

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCefrFilterRow(
    BuildContext context,
    BookProvider provider,
    bool isDark,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(context, provider, isDark, null, 'All'),
          ..._cefrLevels.map(
            (l) => _filterChip(context, provider, isDark, l, l),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    BuildContext context,
    BookProvider provider,
    bool isDark,
    String? level,
    String label,
  ) {
    final isSelected = provider.selectedCefrLevel == level;
    return GestureDetector(
      onTap: () {
        provider.setCefrFilter(level);
        provider.loadRecommendedBooks(cefrLevel: level);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : isDark
              ? AppColors.surfaceDarkElevated
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
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
                ? Colors.white70
                : AppColors.textGrey,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildLevelSection(
    BuildContext context,
    String level,
    List<Book> books,
    bool isDark,
  ) {
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
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            itemBuilder: (context, i) => BookCard(
              book: books[i],
              onTap: () => _openBook(context, books[i]),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBookGrid(BuildContext context, List<Book> books, bool isDark) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.56,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (context, i) =>
          BookCard(book: books[i], onTap: () => _openBook(context, books[i])),
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
