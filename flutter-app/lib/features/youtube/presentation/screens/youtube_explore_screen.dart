import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/youtube_entities.dart';
import '../providers/youtube_provider.dart';

/// YouTube Explore Screen — main discovery page for English learning videos.
///
/// Layout: Search bar → Curated Channels carousel → Search results grid.
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
      final provider = context.read<YouTubeProvider>();
      provider.clearSearch();
      provider.loadChannels();
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

  void _onBackPressed() {
    final provider = context.read<YouTubeProvider>();
    if (provider.searchQuery.isNotEmpty) {
      _searchController.clear();
      provider.clearSearch();
    } else {
      Navigator.pop(context);
    }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPersistentHeader(
                floating: true,
                delegate: _YouTubeFloatingHeader(onBack: _onBackPressed),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: _buildSearchBar(isDark),
                ),
              ),

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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'youtube.channelsTitle'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),

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

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'youtube.browseByCategory'.tr(),
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
    final gradient = _channelGradient(channel.id, channel.category);

    return GestureDetector(
      onTap: () {
        context.read<YouTubeProvider>().loadChannelVideos(
          channel.id,
          channelName: channel.name,
        );
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
              color: gradient.first.withValues(alpha: 0.35),
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
              // Channel avatar — real thumbnail or fallback icon
              _buildChannelAvatar(channel, isDark),
              const Spacer(),
              Text(
                channel.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  channel.level,
                  style: const TextStyle(
                    color: Colors.white,
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

  Widget _buildChannelAvatar(YouTubeChannel channel, bool isDark) {
    // Only load thumbnails routed through our proxy or proper CDN (guards against
    // malformed URLs from stale server-side cache, e.g. yt3.googleusercontent.com/ChannelName)
    final thumb = channel.thumbnail;
    final isUsable = thumb.isNotEmpty &&
        (thumb.contains('/podcasts/proxy/') || thumb.contains('/ytc/'));
    if (isUsable) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: thumb,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (_, __) => _channelAvatarFallback(),
          errorWidget: (_, __, ___) => _channelAvatarFallback(),
        ),
      );
    }
    return _channelAvatarFallback();
  }

  Widget _channelAvatarFallback() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.play_circle_fill_rounded,
        color: Colors.white,
        size: 28,
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
  //  Search Results / Channel Videos
  // ──────────────────────────────────────

  Widget _buildSearchResults(YouTubeProvider provider, bool isDark) {
    // Channel videos are loading
    if (provider.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: LottieLoadingWidget.medium()),
      );
    }

    if (provider.isSearching && provider.searchResults.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: LottieLoadingWidget.medium()),
      );
    }

    if (provider.searchResults.isEmpty) {
      // Show error state with actionable message when the API call failed.
      if (provider.error != null) {
        return SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 64,
                    color: AppColors.grey400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _localizedApiError(provider.error!),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey500, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 64, color: AppColors.grey400),
              const SizedBox(height: 12),
              Text(
                'youtube.noVideos'.tr(),
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
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // Section header showing channel name or search query
            if (index == 0 && provider.activeChannelName.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.subscriptions_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        provider.activeChannelName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        context.read<YouTubeProvider>().clearSearch();
                        setState(() {});
                      },
                      child: const Text('Back'),
                    ),
                  ],
                ),
              );
            }

            final videoIndex = provider.activeChannelName.isNotEmpty
                ? index - 1
                : index;

            if (videoIndex < 0) return const SizedBox.shrink();

            if (videoIndex == provider.searchResults.length) {
              return provider.isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: LottieLoadingWidget.medium()),
                    )
                  : const SizedBox.shrink();
            }

            if (videoIndex >= provider.searchResults.length) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildVideoCard(provider.searchResults[videoIndex], isDark),
            );
          },
          childCount: provider.searchResults.length +
              (provider.activeChannelName.isNotEmpty ? 1 : 0) +
              1,
        ),
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
                    CachedNetworkImage(
                      imageUrl: video.thumbnailUrl.isNotEmpty
                          ? video.thumbnailUrl
                          : 'https://img.youtube.com/vi/${video.videoId}/hqdefault.jpg',
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_outline,
                            size: 48,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        child: const Icon(
                          Icons.play_circle_outline,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    // Dark gradient overlay
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
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
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
                            style: const TextStyle(
                              color: Colors.white,
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

  /// Map API error strings to user-friendly Vietnamese messages.
  String _localizedApiError(String error) {
    if (error.contains('503') || error.contains('unavailable')) {
      return 'Dịch vụ video tạm thời không khả dụng. Vui lòng thử lại sau.';
    }
    if (error.contains('429') || error.contains('quota') || error.contains('exhausted')) {
      return 'Đã đạt giới hạn tìm kiếm hôm nay. Vui lòng thử lại vào ngày mai.';
    }
    if (error.contains('504') || error.contains('timeout')) {
      return 'Yêu cầu mất quá nhiều thời gian. Kiểm tra kết nối mạng và thử lại.';
    }
    if (error.contains('401') || error.contains('403')) {
      return 'Không có quyền truy cập dịch vụ video. Vui lòng liên hệ hỗ trợ.';
    }
    return 'Không thể tải video. Kiểm tra kết nối mạng và thử lại.';
  }

  /// Each channel gets a unique gradient so cards are visually distinct.
  List<Color> _channelGradient(String channelId, String category) {
    switch (channelId) {
      // BBC Learning English — blue gradient
      case 'UCHaHD477h-FeBbrgBrwTDpA':
        return [const Color(0xFF1565C0), const Color(0xFF42A5F5)];
      // TED-Ed — purple/indigo
      case 'UCsooa4yRKGN_zEE8iknghZA':
        return [const Color(0xFF7C4DFF), const Color(0xFF536DFE)];
      // English with Lucy — teal/green
      case 'UCz4tgANd4yy8Oe0iXCdSWfA':
        return [const Color(0xFF00897B), const Color(0xFF26C6DA)];
      // EngVid — orange
      case 'UCVBErcpqaokOf4fI5j73K_w':
        return [const Color(0xFFEF6C00), const Color(0xFFFFCA28)];
      // Rachel's English — pink/red (pronunciation)
      case 'UCvn_XCl_mgQmt3sD753MZ0Q':
        return [const Color(0xFFE91E63), const Color(0xFFFF5252)];
      // VOA Learning English — green (news)
      case 'UCkowKaGPT_yWCebvqN0wBmA':
        return [AppColors.teal, const Color(0xFF26A69A)];
      default:
        // Fallback per category
        switch (category) {
          case 'pronunciation':
            return [const Color(0xFFE91E63), const Color(0xFFFF5252)];
          case 'academic':
            return [const Color(0xFF7C4DFF), const Color(0xFF536DFE)];
          case 'news':
            return [AppColors.teal, const Color(0xFF26A69A)];
          default:
            return [AppColors.primary, const Color(0xFF42A5F5)];
        }
    }
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

// ──────────────────────────────────────
//  Floating Header Delegate
// ──────────────────────────────────────

class _YouTubeFloatingHeader extends SliverPersistentHeaderDelegate {
  final VoidCallback onBack;

  const _YouTubeFloatingHeader({required this.onBack});

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
          IconButton(
            onPressed: onBack,
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
              'youtube.exploreTitle'.tr(),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_YouTubeFloatingHeader old) => old.onBack != onBack;
}
