import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/news_entities.dart';
import '../providers/news_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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
      body: ContentWidth(
        child: SafeArea(
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
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'news.loadError'.tr(),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'news.noArticles'.tr(),
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // One 16:9 card per row is right on a phone; on a tablet
                    // it makes each article taller than half the screen.
                    final columns =
                        ContentWidth.isTablet(MediaQuery.sizeOf(context).width)
                        ? 2
                        : 1;
                    final articles = provider.articles;
                    final rows = (articles.length / columns).ceil();
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, row) {
                          if (row == rows) {
                            return provider.isLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(AppSpacing.lg),
                                    child: Center(
                                      child: LottieLoadingWidget.tiny(),
                                    ),
                                  )
                                : const SizedBox.shrink();
                          }
                          final first = row * columns;
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.lg,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (
                                  var i = first;
                                  i < first + columns;
                                  i++
                                ) ...[
                                  if (i > first)
                                    const SizedBox(width: AppSpacing.lg),
                                  Expanded(
                                    child: i < articles.length
                                        ? _buildArticleCard(articles[i], isDark)
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }, childCount: rows + 1),
                      ),
                    );
                  },
                ),
              ],
            ),
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
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              selected: isSelected,
              showCheckmark: false,
              avatar: Icon(
                categoryIcons[cat.id] ?? Icons.article_rounded,
                size: 16,
                color: isSelected
                    ? AppColors.onGradient
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              label: Text(
                cat.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isSelected
                      ? AppColors.onGradient
                      : (isDark
                            ? AppColors.onGradient.withValues(alpha: 0.7)
                            : Theme.of(context).colorScheme.onSurface),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              backgroundColor: isDark
                  ? AppColors.onGradient.withValues(alpha: 0.06)
                  : AppColors.grey100,
              selectedColor: Theme.of(context).colorScheme.primary,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
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
        trackContentInteraction(
          itemType: 'news',
          itemId: article.id,
          action: 'open',
          topic: article.category,
          source: 'news_list',
        );
        Navigator.pushNamed(context, '/news/detail', arguments: article);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.onGradient.withValues(alpha: 0.06)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: 0.05),

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
                              Theme.of(
                                context,
                              ).colorScheme.shadow.withValues(alpha: 0.5),
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
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: cefrColor,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
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
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.surfaceLight,
                                  fontWeight: FontWeight.w800,
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
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.shadow.withValues(alpha: 0.6),

                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 12,
                                color: AppColors.onGradient.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                'course.durationMin'.tr(
                                  namedArgs: {
                                    'count': '${article.readingTimeMin}',
                                  },
                                ),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: AppColors.onGradient.withValues(
                                        alpha: 0.7,
                                      ),
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
                        right: 12,
                        child: Text(
                          article.sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.onGradient.withValues(
                                  alpha: 0.7,
                                ),
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
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      article.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.onGradient.withValues(alpha: 0.6)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
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
                            horizontal: AppSpacing.sm,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cefrColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: cefrColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            word,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cefrColor,
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
        return context.status.success;
      case 'A2':
        return AppColors.greenSuccessSoft;
      case 'B1':
        return context.status.warning;
      case 'B2':
        return AppColors.orange;
      case 'C1':
        return AppColors.deepOrange;
      case 'C2':
        return AppColors.purple;
      default:
        return Theme.of(context).colorScheme.primary;
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
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          AppBackButton(
            onPressed: () => Navigator.pop(context),
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'news.title'.tr(),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_NewsFloatingHeader old) => false;
}
