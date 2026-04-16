import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/youtube_entities.dart';
import '../providers/youtube_provider.dart';

/// YouTube Explore Screen — main discovery page for English learning videos.
///
/// Layout: Search bar → Curated Channels carousel → Search results grid.
/// Follows ui-ux-pro-max design methodology.
///
/// Phase 1: YouTube Video Integration.
class YouTubeExploreScreen extends StatefulWidget {
  const YouTubeExploreScreen({super.key});

  @override
  State<YouTubeExploreScreen> createState() => _YouTubeExploreScreenState();
}

class _YouTubeExploreScreenState extends State<YouTubeExploreScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<YouTubeProvider>().loadChannels();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<YouTubeProvider>().loadMoreResults();
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.length >= 2) {
        context.read<YouTubeProvider>().searchVideos(query);
      } else if (query.isEmpty) {
        context.read<YouTubeProvider>().clearSearch();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // ── Header + Search ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                            'English Videos',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSearchBar(isDark),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── Curated Channels or Search Results ──
            Consumer<YouTubeProvider>(
              builder: (context, provider, _) {
                if (provider.searchQuery.isNotEmpty) {
                  return _buildSearchResults(provider, isDark);
                }
                return _buildChannelsSection(provider, isDark);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Search Bar
  // ──────────────────────────────────────

  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.grey200,
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search English learning videos...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white54 : AppColors.textGrey,
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white38 : AppColors.textGrey,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    context.read<YouTubeProvider>().clearSearch();
                    setState(() {});
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Curated Channels Section
  // ──────────────────────────────────────

  Widget _buildChannelsSection(YouTubeProvider provider, bool isDark) {
    if (provider.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: LottieLoadingWidget.medium()),
      );
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'English Learning Channels',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),

        // Channel cards
        SizedBox(
          height: 180,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: provider.channels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _buildChannelCard(provider.channels[index], isDark),
          ),
        ),

        const SizedBox(height: 28),

        // Quick categories
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Browse by Category',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCategoryChip(
                'General',
                Icons.school_rounded,
                AppColors.primary,
              ),
              _buildCategoryChip(
                'Pronunciation',
                Icons.record_voice_over_rounded,
                const Color(0xFFE91E63),
              ),
              _buildCategoryChip(
                'Academic',
                Icons.auto_stories_rounded,
                AppColors.purple,
              ),
              _buildCategoryChip(
                'News',
                Icons.newspaper_rounded,
                AppColors.teal,
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _buildChannelCard(YouTubeChannel channel, bool isDark) {
    final gradient = _channelGradient(channel.category);
    final iconTileBg = isDark
      ? Colors.black.withValues(alpha: 0.28)
      : Colors.white.withValues(alpha: 0.92);
    final iconColor = isDark
      ? AppColors.surfaceLight
      : gradient.first.withValues(alpha: 0.95);
    final levelChipBg = isDark
      ? Colors.white.withValues(alpha: 0.20)
      : Colors.white.withValues(alpha: 0.92);
    final levelChipTextColor = isDark
      ? AppColors.surfaceLight
      : AppColors.textDark;

    return GestureDetector(
      onTap: () {
        context.read<YouTubeProvider>().loadChannelVideos(channel.id);
        _searchController.text = channel.name;
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 200,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Channel icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconTileBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: iconColor,
                  size: 28,
                ),
              ),
              const Spacer(),
              Text(
                channel.name,
                style: TextStyle(
                  color: AppColors.surfaceLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: levelChipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  channel.level,
                  style: TextStyle(
                    color: levelChipTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, IconData icon, Color color) {
    return ActionChip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      onPressed: () {
        context.read<YouTubeProvider>().loadChannels(
          category: label.toLowerCase(),
        );
      },
    );
  }

  // ──────────────────────────────────────
  //  Search Results
  // ──────────────────────────────────────

  Widget _buildSearchResults(YouTubeProvider provider, bool isDark) {
    if (provider.isSearching && provider.searchResults.isEmpty) {
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
                Icons.search_off_rounded,
                size: 64,
                color: AppColors.grey400,
              ),
              const SizedBox(height: 12),
              Text(
                'No videos found',
                style: TextStyle(color: AppColors.grey500, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == provider.searchResults.length) {
            return provider.isSearching
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: LottieLoadingWidget.medium()),
                  )
                : const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildVideoCard(provider.searchResults[index], isDark),
          );
        }, childCount: provider.searchResults.length + 1),
      ),
    );
  }

  Widget _buildVideoCard(YouTubeVideo video, bool isDark) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/youtube/player', arguments: video);
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
            // Thumbnail
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
                      video.thumbnailUrl.isNotEmpty
                          ? video.thumbnailUrl
                          : 'https://via.placeholder.com/480x270',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        child: const Icon(
                          Icons.play_circle_outline,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    // Play overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.4),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: AppColors.surfaceLight,
                        size: 48,
                      ),
                    ),
                    // CEFR level badge (skill: content-difficulty-levels)
                    if (video.cefrLevel.isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _cefrColor(video.cefrLevel),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            video.cefrLevel,
                            style: TextStyle(
                              color: AppColors.surfaceLight,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.channelTitle,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : AppColors.textGrey,
                      fontSize: 12,
                    ),
                  ),
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

  List<Color> _channelGradient(String category) {
    switch (category) {
      case 'pronunciation':
        return [const Color(0xFFE91E63), const Color(0xFFFF5252)];
      case 'academic':
        return [const Color(0xFF7C4DFF), const Color(0xFF536DFE)];
      case 'news':
        return [AppColors.teal, const Color(0xFF26A69A)];
      default:
        return [AppColors.primary, AppColors.primary];
    }
  }

  // CEFR color map (skill: content-difficulty-levels)
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
