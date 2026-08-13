import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/news_entities.dart';
import '../providers/news_provider.dart';

/// News List Screen — browse English news articles by category and CEFR level.
///
/// Layout: CEFR level filter → Category tabs → Article cards with pull-to-refresh.
///
/// Phase 2: News Reading.
class NewsListScreen extends StatefulWidget {
  const NewsListScreen({super.key});

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NewsProvider>();
      provider.loadCategories();
      provider.loadArticles(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<NewsProvider>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              context.read<NewsProvider>().loadArticles(refresh: true),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // ── Header (floating: hiện ngay khi scroll lên) ──
              const SliverPersistentHeader(
                floating: true,
                delegate: _NewsFloatingHeader(),
              ),

              // ── Category Tabs ──
              SliverToBoxAdapter(
                child: Consumer<NewsProvider>(
                  builder: (context, provider, _) {
                    return _buildCategoryTabs(provider, isDark);
                  },
                ),
              ),

              // ── Articles ──
              Consumer<NewsProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.articles.isEmpty) {
                    return const SliverFillRemaining(
                      child: Center(child: LottieLoadingWidget.medium()),
                    );
                  }

                  if (provider.error != null && provider.articles.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: Colors.red.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'news.loadError'.tr(),
                              style: TextStyle(color: AppColors.grey500),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () =>
                                  provider.loadArticles(refresh: true),
                              child: Text('common.retry'.tr()),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (provider.articles.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 64,
                              color: AppColors.grey400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'news.noArticles'.tr(),
                              style: TextStyle(
                                color: AppColors.grey500,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index == provider.articles.length) {
                          return provider.isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: LottieLoadingWidget.tiny(),
                                  ),
                                )
                              : const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildArticleCard(
                            provider.articles[index],
                            isDark,
                          ),
                        );
                      }, childCount: provider.articles.length + 1),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Category Tabs
  // ──────────────────────────────────────

  Widget _buildCategoryTabs(NewsProvider provider, bool isDark) {
    final categoryIcons = {
      'general': Icons.public_rounded,
      'technology': Icons.devices_rounded,
      'science': Icons.science_rounded,
      'health': Icons.favorite_rounded,
      'business': Icons.business_rounded,
      'entertainment': Icons.movie_rounded,
      'sports': Icons.sports_rounded,
      'education': Icons.school_rounded,
    };

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: provider.categories.map((cat) {
          final isSelected = provider.selectedCategory == cat.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              showCheckmark: false,
              avatar: Icon(
                categoryIcons[cat.id] ?? Icons.article_rounded,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textGrey,
              ),
              label: Text(
                cat.label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : AppColors.textDark),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : AppColors.grey100,
              selectedColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide.none,
              onSelected: (_) => provider.selectCategory(cat.id),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Article Card
  // ──────────────────────────────────────

  Widget _buildArticleCard(NewsArticle article, bool isDark) {
    final cefrColor = _cefrColor(article.cefrLevel);

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/news/detail', arguments: article);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (article.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        article.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: cefrColor.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.article_rounded,
                            size: 48,
                            color: cefrColor,
                          ),
                        ),
                      ),
                      // Gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.5),
                            ],
                          ),
                        ),
                      ),
                      // CEFR Badge
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cefrColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: cefrColor.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            article.cefrLevel,
                            style: TextStyle(
                              color: AppColors.surfaceLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      // Reading time
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 12,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'course.durationMin'.tr(namedArgs: {'count': '${article.readingTimeMin}'}),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Source
                      Positioned(
                        bottom: 8,
                        left: 12,
                        child: Text(
                          article.sourceName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      article.description,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : AppColors.textGrey,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (article.highlightedWords.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: article.highlightedWords.take(4).map((word) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cefrColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: cefrColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            word,
                            style: TextStyle(
                              color: cefrColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
}

// ──────────────────────────────────────
//  Floating Header Delegate
// ──────────────────────────────────────

class _NewsFloatingHeader extends SliverPersistentHeaderDelegate {
  const _NewsFloatingHeader();

  static const double _height = 72.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  FloatingHeaderSnapConfiguration get snapConfiguration =>
      FloatingHeaderSnapConfiguration(
        curve: Curves.easeOut,
        duration: const Duration(milliseconds: 200),
      );

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          AppBackButton(
            onPressed: () => Navigator.pop(context),
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'news.title'.tr(),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_NewsFloatingHeader old) => false;
}
