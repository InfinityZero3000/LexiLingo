import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/youtube_entities.dart';
import '../providers/youtube_provider.dart';

/// YouTube Explore Screen — two tabs: Discover + Saved videos.
class YouTubeExploreScreen extends StatefulWidget {
  const YouTubeExploreScreen({super.key});

  @override
  State<YouTubeExploreScreen> createState() => _YouTubeExploreScreenState();
}

class _YouTubeExploreScreenState extends State<YouTubeExploreScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  late final YouTubeProvider _youtubeProvider;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _youtubeProvider = context.read<YouTubeProvider>();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _youtubeProvider.clearSearch();
      _youtubeProvider.loadChannels();
      _youtubeProvider.loadSavedVideos();
      _youtubeProvider.loadRecommendations();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _youtubeProvider.clearAll();
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onBackPressed() {
    if (_youtubeProvider.searchQuery.isNotEmpty) {
      _searchController.clear();
      _youtubeProvider.clearSearch();
    } else {
      Navigator.pop(context);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _youtubeProvider.loadMoreResults();
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
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : const Color(0xFFF7F8FC),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(isDark),
              _buildSearchBar(isDark),
              Expanded(
                child: Consumer<YouTubeProvider>(
                  builder: (context, provider, _) {
                    if (provider.searchQuery.isNotEmpty) {
                      return _buildSearchResults(provider, isDark);
                    }
                    return Column(
                      children: [
                        _buildTabBar(isDark),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildHomeContent(provider, isDark),
                              _buildRecommendationsTab(provider, isDark),
                              _buildSavedTab(provider, isDark),
                              _buildHistoryTab(provider, isDark),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Header
  // ──────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _onBackPressed,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white,
              foregroundColor: isDark ? Colors.white : AppColors.textDark,
              padding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'youtube.exploreTitle'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Học tiếng Anh qua video',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showGuideDialog(isDark),
            icon: const Icon(Icons.help_outline_rounded),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white,
              foregroundColor: isDark ? Colors.white70 : AppColors.textGrey,
              padding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(width: 8),
          Consumer<YouTubeProvider>(
            builder: (context, provider, _) {
              final count = provider.savedVideos.length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: () {
                      if (_youtubeProvider.searchQuery.isNotEmpty) {
                        _searchController.clear();
                        _youtubeProvider.clearSearch();
                      }
                      _tabController.animateTo(2); // Index 2 is Saved tab
                    },
                    icon: const Icon(Icons.bookmark_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white,
                      foregroundColor: count > 0
                          ? AppColors.primary
                          : AppColors.textGrey,
                      padding: const EdgeInsets.all(10),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
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

  // ──────────────────────────────────────
  //  Search Bar
  // ──────────────────────────────────────

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
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
          onChanged: (q) {
            _onSearchChanged(q);
            setState(() {});
          },
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Tìm video học tiếng Anh...',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : AppColors.textGrey,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: isDark ? Colors.white30 : AppColors.textGrey,
              size: 20,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      context.read<YouTubeProvider>().clearSearch();
                      setState(() {});
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Discover Tab
  // ──────────────────────────────────────

  Widget _buildDiscoverTab(bool isDark) {
    return Consumer<YouTubeProvider>(
      builder: (context, provider, _) {
        if (provider.searchQuery.isNotEmpty) {
          return _buildSearchResults(provider, isDark);
        }
        return _buildHomeContent(provider, isDark);
      },
    );
  }

  Widget _buildHomeContent(YouTubeProvider provider, bool isDark) {
    if (provider.isLoading) {
      return const Center(child: LottieLoadingWidget.medium());
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Kênh học tiếng Anh',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 160,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: provider.channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  _buildChannelCard(provider.channels[index], isDark),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.category_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Theo chủ đề',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kCategories
                  .map((cat) => _buildCategoryChip(cat, isDark))
                  .toList(),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  static const _kCategories = [
    _CategoryInfo(
      'Tổng quát',
      Icons.school_rounded,
      Color(0xFF2196F3),
      'general',
    ),
    _CategoryInfo(
      'Phát âm',
      Icons.record_voice_over_rounded,
      Color(0xFFE91E63),
      'pronunciation',
    ),
    _CategoryInfo(
      'Học thuật',
      Icons.auto_stories_rounded,
      Color(0xFF7C4DFF),
      'academic',
    ),
    _CategoryInfo(
      'Tin tức',
      Icons.newspaper_rounded,
      Color(0xFF009688),
      'news',
    ),
  ];

  Widget _buildCategoryChip(_CategoryInfo cat, bool isDark) {
    return GestureDetector(
      onTap: () =>
          context.read<YouTubeProvider>().loadChannels(category: cat.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: cat.color.withValues(alpha: isDark ? 0.15 : 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cat.color.withValues(alpha: isDark ? 0.25 : 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(cat.icon, size: 16, color: cat.color),
            const SizedBox(width: 6),
            Text(
              cat.label,
              style: TextStyle(
                color: cat.color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Channel Cards
  // ──────────────────────────────────────

  Widget _buildChannelCard(YouTubeChannel channel, bool isDark) {
    final gradient = _channelGradient(channel.id, channel.category);

    return GestureDetector(
      onTap: () {
        context.read<YouTubeProvider>().loadChannelVideos(
          channel.id,
          channelName: channel.name,
        );
      },
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChannelAvatar(channel),
              const Spacer(),
              Text(
                channel.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  channel.level,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelAvatar(YouTubeChannel channel) {
    final thumb = channel.thumbnail;
    final isUsable =
        thumb.isNotEmpty &&
        (thumb.contains('/podcasts/proxy/') || thumb.contains('/ytc/'));
    if (isUsable) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: thumb,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (_, __) => _avatarFallback(),
          errorWidget: (_, __, ___) => _avatarFallback(),
        ),
      );
    }
    return _avatarFallback();
  }

  Widget _avatarFallback() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.play_circle_fill_rounded,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  // ──────────────────────────────────────
  //  Search Results
  // ──────────────────────────────────────

  Widget _buildSearchResults(YouTubeProvider provider, bool isDark) {
    if (provider.isLoading ||
        (provider.isSearching && provider.searchResults.isEmpty)) {
      return const Center(child: LottieLoadingWidget.medium());
    }

    if (provider.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: AppColorRoles.textMuted(isDark),
            ),
            const SizedBox(height: 12),
            Text(
              provider.error != null
                  ? _localizedApiError(provider.error!)
                  : 'youtube.noVideos'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColorRoles.textSecondary(isDark),
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (provider.activeChannelName.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      context.read<YouTubeProvider>().clearSearch();
                      setState(() {});
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Quay lại'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index >= provider.searchResults.length) {
                return provider.isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: LottieLoadingWidget.medium()),
                      )
                    : const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildVideoCard(provider.searchResults[index], isDark),
              );
            }, childCount: provider.searchResults.length + 1),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────
  //  Video Card (compact horizontal)
  // ──────────────────────────────────────

  Widget _buildVideoCard(YouTubeVideo video, bool isDark) {
    return Consumer<YouTubeProvider>(
      builder: (context, provider, _) {
        final isSaved = provider.isVideoSaved(video.videoId);

        return GestureDetector(
          onTap: () =>
              Navigator.pushNamed(context, '/youtube/player', arguments: video),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                  child: SizedBox(
                    width: 120,
                    height: 80,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: video.thumbnailUrl.isNotEmpty
                              ? video.thumbnailUrl
                              : 'https://img.youtube.com/vi/${video.videoId}/mqdefault.jpg',
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: AppColors.primary.withValues(alpha: 0.08),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            child: const Icon(
                              Icons.play_circle_outline,
                              size: 32,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.35),
                              ],
                            ),
                          ),
                        ),
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        if (video.cefrLevel.isNotEmpty)
                          Positioned(
                            top: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _cefrColor(video.cefrLevel),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                video.cefrLevel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          video.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : AppColors.textDark,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          video.channelTitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : AppColors.textGrey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                // Action buttons column
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        if (isSaved) {
                          provider.unsaveVideo(video.videoId);
                        } else {
                          provider.saveVideo(video);
                        }
                      },
                      icon: Icon(
                        isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 22,
                        color: isSaved ? AppColors.primary : AppColors.grey400,
                      ),
                    ),
                    IconButton(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      onPressed: () => _shareVideo(video),
                      icon: Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: isDark ? Colors.white30 : AppColors.grey400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────
  //  Saved Videos Popup
  // ──────────────────────────────────────

  void _showSavedPopup(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SavedVideosSheet(isDark: isDark),
    );
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  void _shareVideo(YouTubeVideo video) async {
    final url = Uri.parse('https://www.youtube.com/watch?v=${video.videoId}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _localizedApiError(String error) {
    if (error.contains('503') || error.contains('unavailable')) {
      return 'Dịch vụ video tạm thời không khả dụng.\nVui lòng thử lại sau.';
    }
    if (error.contains('429') ||
        error.contains('quota') ||
        error.contains('exhausted')) {
      return 'Đã đạt giới hạn tìm kiếm hôm nay.\nVui lòng thử lại vào ngày mai.';
    }
    if (error.contains('504') || error.contains('timeout')) {
      return 'Yêu cầu mất quá nhiều thời gian.\nKiểm tra kết nối mạng và thử lại.';
    }
    if (error.contains('401') || error.contains('403')) {
      return 'Không có quyền truy cập.\nVui lòng liên hệ hỗ trợ.';
    }
    return 'Không thể tải video.\nKiểm tra kết nối mạng và thử lại.';
  }

  List<Color> _channelGradient(String channelId, String category) {
    switch (channelId) {
      case 'UCHaHD477h-FeBbVh9Sh7syA': // BBC Learning English
        return [const Color(0xFF1565C0), const Color(0xFF42A5F5)];
      case 'UCsooa4yRKGN_zEE8iknghZA': // TED-Ed
        return [const Color(0xFF7C4DFF), const Color(0xFF536DFE)];
      case 'UCz4tgANd4yy8Oe0iXCdSWfA': // English with Lucy
        return [const Color(0xFF00897B), const Color(0xFF26C6DA)];
      case 'UCVBErcpqaokOf4fI5j73K_w': // EngVid
        return [const Color(0xFFEF6C00), const Color(0xFFFFCA28)];
      case 'UCvn_XCl_mgQmt3sD753zdJA': // Rachel's English
        return [const Color(0xFFE91E63), const Color(0xFFFF5252)];
      case 'UCKyTokYo0nK2OA-az-sDijA': // VOA Learning English
        return [AppColors.teal, const Color(0xFF26A69A)];
      default:
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

  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? Colors.white60 : AppColors.textGrey,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        padding: const EdgeInsets.all(4),
        tabs: const [
          Tab(text: 'Khám phá'),
          Tab(text: 'Đề xuất'),
          Tab(text: 'Đã lưu'),
          Tab(text: 'Lịch sử'),
        ],
      ),
    );
  }

  Widget _buildRecommendationsTab(YouTubeProvider provider, bool isDark) {
    if (provider.isLoadingRecommendations) {
      return const Center(child: LottieLoadingWidget.medium());
    }

    final videos = provider.recommendedVideos;
    if (videos.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => provider.loadRecommendations(),
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              Icon(Icons.auto_awesome_rounded, size: 64, color: isDark ? Colors.white24 : AppColors.grey300),
              const SizedBox(height: 16),
              Text(
                'Chưa có đề xuất nào',
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hãy xem một vài video để chúng tôi gợi ý những nội dung phù hợp cho bạn.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white30 : AppColors.textGrey,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => provider.loadRecommendations(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tải lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadRecommendations(),
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildVideoCard(videos[index], isDark);
        },
      ),
    );
  }

  Widget _buildSavedTab(YouTubeProvider provider, bool isDark) {
    final saved = provider.savedVideos;
    if (saved.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded,
                size: 64,
                color: isDark ? Colors.white24 : AppColors.grey300),
            const SizedBox(height: 16),
            Text(
              'Chưa có video nào được lưu',
              style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nhấn biểu tượng bookmark trên video để lưu lại học sau.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white30 : AppColors.textGrey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: saved.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final s = saved[index];
        final video = YouTubeVideo(
          videoId: s.videoId,
          title: s.title,
          description: '',
          channelTitle: s.channelTitle,
          channelId: '',
          publishedAt: '',
          thumbnailUrl: s.thumbnailUrl,
          cefrLevel: s.cefrLevel,
        );
        return _buildVideoCard(video, isDark);
      },
    );
  }

  Widget _buildHistoryTab(YouTubeProvider provider, bool isDark) {
    final history = provider.watchHistory;
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded,
                size: 64,
                color: isDark ? Colors.white24 : AppColors.grey300),
            const SizedBox(height: 16),
            Text(
              'Lịch sử trống',
              style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Các video bạn đã xem sẽ xuất hiện tại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white30 : AppColors.textGrey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showClearHistoryDialog(provider),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('Xóa lịch sử'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _buildVideoCard(history[index], isDark);
            },
          ),
        ),
      ],
    );
  }

  void _showClearHistoryDialog(YouTubeProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa lịch sử xem'),
        content: const Text('Bạn có chắc chắn muốn xóa toàn bộ lịch sử xem video không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              provider.clearWatchHistory();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  void _showGuideDialog(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Cẩm nang học tiếng Anh',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Học qua video là phương pháp cực kỳ hiệu quả để nâng cao phản xạ tiếng Anh tự nhiên. Hãy tận dụng tối đa các công cụ hỗ trợ:',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : AppColors.textGrey,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                _buildGuideItem(
                  icon: Icons.subtitles_rounded,
                  color: Colors.blue,
                  title: 'Phụ đề tương tác thời gian thực',
                  desc: 'Phụ đề hiển thị chạy song song dưới video player. Chạm trực tiếp vào bất kỳ từ nào để tra nghĩa nhanh.',
                  isDark: isDark,
                ),
                _buildGuideItem(
                  icon: Icons.bookmark_add_rounded,
                  color: Colors.green,
                  title: 'Lưu từ vựng nhanh 1 chạm',
                  desc: 'Khi mở bảng dịch nghĩa, chỉ cần nhấn "Lưu từ" để thêm ngay từ vựng vào Sổ tay từ vựng của bạn mà không có thêm màn hình trung gian.',
                  isDark: isDark,
                ),
                _buildGuideItem(
                  icon: Icons.repeat_rounded,
                  color: Colors.purple,
                  title: 'Phương pháp Shadowing',
                  desc: 'Tạm dừng sau mỗi câu nói của người bản xứ và lặp lại thật to để cải thiện phát âm, ngữ điệu và trọng âm.',
                  isDark: isDark,
                ),
                _buildGuideItem(
                  icon: Icons.history_edu_rounded,
                  color: Colors.orange,
                  title: 'Xem lại lịch sử tra cứu',
                  desc: 'Trong khi phát video, lịch sử các từ bạn đã tra trong phiên học sẽ được hiển thị ngay bên dưới để ôn tập tức thì.',
                  isDark: isDark,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Bắt đầu học ngay',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuideItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.15 : 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
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

// ──────────────────────────────────────
//  Saved Videos Bottom Sheet
// ──────────────────────────────────────

class _SavedVideosSheet extends StatelessWidget {
  final bool isDark;
  const _SavedVideosSheet({required this.isDark});

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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    if (diff.inDays < 30) return '${diff.inDays} ngày trước';
    return '${diff.inDays ~/ 30} tháng trước';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.backgroundDark : const Color(0xFFF7F8FC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle + header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : AppColors.grey300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.bookmark_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Video đã lưu',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Consumer<YouTubeProvider>(
                          builder: (_, provider, __) => Text(
                            '${provider.savedVideos.length} video',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white38
                                  : AppColors.textGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? Colors.white12 : AppColors.grey200,
              ),
              // Content
              Expanded(
                child: Consumer<YouTubeProvider>(
                  builder: (context, provider, _) {
                    final saved = provider.savedVideos;

                    if (saved.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_border_rounded,
                              size: 64,
                              color: isDark
                                  ? Colors.white24
                                  : AppColors.grey300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Chưa có video nào được lưu',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white38
                                    : AppColors.textGrey,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Nhấn  trên thẻ video để lưu lại',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white24
                                    : AppColors.grey400,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: saved.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final s = saved[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            final video = YouTubeVideo(
                              videoId: s.videoId,
                              title: s.title,
                              description: '',
                              channelTitle: s.channelTitle,
                              channelId: '',
                              publishedAt: '',
                              thumbnailUrl: s.thumbnailUrl,
                              cefrLevel: s.cefrLevel,
                            );
                            Navigator.pushNamed(
                              context,
                              '/youtube/player',
                              arguments: video,
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(16),
                                  ),
                                  child: SizedBox(
                                    width: 120,
                                    height: 80,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CachedNetworkImage(
                                          imageUrl: s.thumbnailUrl.isNotEmpty
                                              ? s.thumbnailUrl
                                              : 'https://img.youtube.com/vi/${s.videoId}/mqdefault.jpg',
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => Container(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.08,
                                            ),
                                          ),
                                          errorWidget: (_, __, ___) =>
                                              Container(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.08),
                                                child: const Icon(
                                                  Icons.play_circle_outline,
                                                  size: 32,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                        ),
                                        Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.transparent,
                                                Colors.black.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const Center(
                                          child: Icon(
                                            Icons.play_circle_fill_rounded,
                                            color: Colors.white,
                                            size: 30,
                                          ),
                                        ),
                                        if (s.cefrLevel.isNotEmpty)
                                          Positioned(
                                            top: 5,
                                            left: 5,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _cefrColor(s.cefrLevel),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                s.cefrLevel,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      6,
                                      8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : AppColors.textDark,
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          s.channelTitle,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.white38
                                                : AppColors.textGrey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Đã lưu ${_timeAgo(s.savedAt)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark
                                                ? Colors.white24
                                                : AppColors.grey400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                  onPressed: () =>
                                      provider.unsaveVideo(s.videoId),
                                  icon: const Icon(
                                    Icons.bookmark_remove_rounded,
                                    size: 22,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────
//  Category Info record
// ──────────────────────────────────────

class _CategoryInfo {
  final String label;
  final IconData icon;
  final Color color;
  final String key;

  const _CategoryInfo(this.label, this.icon, this.color, this.key);
}
