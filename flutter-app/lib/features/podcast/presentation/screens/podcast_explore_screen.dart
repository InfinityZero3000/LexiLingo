import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/podcast_entities.dart';
import '../providers/podcast_provider.dart';
import '../widgets/podcast_card.dart';
import 'podcast_detail_screen.dart';

/// Main podcast browse screen.
///
/// Provides:
/// - Debounced search bar (500 ms) that shows results as PodcastCard list
/// - Curated categories grouped by CEFR level when not searching
/// - Loading + error states
///
/// Phase 4: Podcast.
class PodcastExploreScreen extends StatefulWidget {
  const PodcastExploreScreen({super.key});

  @override
  State<PodcastExploreScreen> createState() => _PodcastExploreScreenState();
}

class _PodcastExploreScreenState extends State<PodcastExploreScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PodcastProvider>();
      provider.loadCuratedPodcasts();
      provider.loadFollowedPodcasts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    if (query.isEmpty) {
      setState(() => _isTyping = false);
      context.read<PodcastProvider>().clearSearch();
      return;
    }

    setState(() => _isTyping = true);
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<PodcastProvider>().searchPodcasts(query);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() => _isTyping = false);
    context.read<PodcastProvider>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.04),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Podcasts',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Search bar ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search podcasts…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _isTyping || _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _clearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),

            // ── Body: search results or curated categories ──
            Consumer<PodcastProvider>(
              builder: (context, provider, _) {
                // Loading state (initial load only)
                if (provider.isLoading && provider.curatedCategories.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: LottieLoadingWidget.medium()),
                  );
                }

                // Error state
                if (provider.error != null &&
                    provider.curatedCategories.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 52,
                            color: Colors.red.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Failed to load podcasts',
                            style: TextStyle(color: AppColors.grey500),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              provider.clearError();
                              provider.loadCuratedPodcasts();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Search state
                final isSearching = _searchController.text.isNotEmpty;
                if (isSearching) {
                  return _buildSearchResults(provider, isDark);
                }

                // Curated categories
                return _buildCuratedCategories(provider, isDark);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Search results view
  // ──────────────────────────────────────

  Widget _buildSearchResults(PodcastProvider provider, bool isDark) {
    if (provider.isSearching) {
      return const SliverFillRemaining(
        child: Center(child: LottieLoadingWidget.medium()),
      );
    }

    if (provider.searchResults.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.podcasts_rounded,
                size: 64,
                color: AppColors.grey300,
              ),
              const SizedBox(height: 12),
              Text(
                'No podcasts found',
                style: TextStyle(color: AppColors.grey500, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Try a different search term',
                style: TextStyle(color: AppColors.grey400, fontSize: 13),
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
          final podcast = provider.searchResults[index];
          final isFollowed = provider.followedPodcasts.any(
            (f) => f.feedUrl == podcast.feedUrl,
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SearchResultTile(
              podcast: podcast,
              isFollowed: isFollowed,
              onTap: () => _openDetail(podcast),
            ),
          );
        }, childCount: provider.searchResults.length),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Curated categories view
  // ──────────────────────────────────────

  Widget _buildCuratedCategories(PodcastProvider provider, bool isDark) {
    if (provider.curatedCategories.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Text(
            'No curated podcasts yet',
            style: TextStyle(color: AppColors.grey400),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 40),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final category = provider.curatedCategories[index];
          return _buildCategorySection(category, provider, isDark);
        }, childCount: provider.curatedCategories.length),
      ),
    );
  }

  Widget _buildCategorySection(
    PodcastCategory category,
    PodcastProvider provider,
    bool isDark,
  ) {
    final cefrColor = _cefrGroupColor(category.cefrLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              // CEFR chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: cefrColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  category.cefrLevel,
                  style: TextStyle(
                    color: AppColors.surfaceLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Horizontal scroll row
        SizedBox(
          height: 256,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: category.podcasts.length,
            itemBuilder: (context, i) {
              final podcast = category.podcasts[i];
              final isFollowed = provider.followedPodcasts.any(
                (f) => f.feedUrl == podcast.feedUrl,
              );
              return PodcastCard(
                podcast: podcast,
                isFollowed: isFollowed,
                onTap: () => _openDetail(podcast),
              );
            },
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────
  //  Navigation
  // ──────────────────────────────────────

  void _openDetail(Podcast podcast) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PodcastDetailScreen(podcast: podcast)),
    );
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  Color _cefrGroupColor(String level) {
    switch (level) {
      case 'A1':
      case 'A2':
      case 'A1-A2':
        return AppColors.greenSuccessBright; // green
      case 'B1':
      case 'B2':
      case 'B1-B2':
        return const Color(0xFF2196F3); // blue
      case 'C1':
      case 'C2':
      case 'C1-C2':
        return AppColors.purple; // purple
      default:
        return AppColors.primary;
    }
  }
}

// ──────────────────────────────────────
//  Private helper: search result tile
// ──────────────────────────────────────

class _SearchResultTile extends StatelessWidget {
  final Podcast podcast;
  final bool isFollowed;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.podcast,
    required this.isFollowed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(podcast.cefrLevel);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: podcast.artworkUrl.isNotEmpty
                  ? Image.network(
                      podcast.artworkUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: cefrColor.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.podcasts_rounded,
                          color: cefrColor,
                          size: 28,
                        ),
                      ),
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: cefrColor.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.podcasts_rounded,
                        color: cefrColor,
                        size: 28,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    podcast.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    podcast.author,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : AppColors.textGrey,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cefrColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          podcast.cefrLevel,
                          style: TextStyle(
                            color: AppColors.surfaceLight,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${podcast.episodeCount} episodes',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              isFollowed
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: isFollowed
                  ? AppColors.greenSuccess
                  : (isDark ? Colors.white38 : AppColors.grey400),
            ),
          ],
        ),
      ),
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
}
