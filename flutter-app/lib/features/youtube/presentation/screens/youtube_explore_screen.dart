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
  late final TabController _tabController;
  Timer? _debounce;
  late final YouTubeProvider _youtubeProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _youtubeProvider = context.read<YouTubeProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _youtubeProvider.clearSearch();
      _youtubeProvider.loadChannels();
      _youtubeProvider.loadSavedVideos();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _youtubeProvider.clearAll();
    _tabController.dispose();
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
        backgroundColor:
            isDark ? AppColors.backgroundDark : const Color(0xFFF7F8FC),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(isDark),
              _buildSearchBar(isDark),
              _buildTabBar(isDark),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildDiscoverTab(isDark),
                    _buildSavedTab(isDark),
                  ],
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
              backgroundColor:
                  isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
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
          Consumer<YouTubeProvider>(
            builder: (context, provider, _) {
              final count = provider.savedVideos.length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: () => _tabController.animateTo(1),
                    icon: const Icon(Icons.bookmark_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white,
                      foregroundColor:
                          count > 0 ? AppColors.primary : AppColors.textGrey,
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
            color:
                isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.grey200,
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Tab Bar
  // ──────────────────────────────────────

  Widget _buildTabBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.grey200,
          ),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(3),
          labelColor: Colors.white,
          unselectedLabelColor:
              isDark ? Colors.white54 : AppColors.textGrey,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Khám phá'),
            Tab(text: 'Đã lưu'),
          ],
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
                const Icon(Icons.auto_awesome_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Kênh học tiếng Anh',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
                const Icon(Icons.category_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Theo chủ đề',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
    _CategoryInfo('Tổng quát', Icons.school_rounded, Color(0xFF2196F3), 'general'),
    _CategoryInfo('Phát âm', Icons.record_voice_over_rounded, Color(0xFFE91E63), 'pronunciation'),
    _CategoryInfo('Học thuật', Icons.auto_stories_rounded, Color(0xFF7C4DFF), 'academic'),
    _CategoryInfo('Tin tức', Icons.newspaper_rounded, Color(0xFF009688), 'news'),
  ];

  Widget _buildCategoryChip(_CategoryInfo cat, bool isDark) {
    return GestureDetector(
      onTap: () => context.read<YouTubeProvider>().loadChannels(
            category: cat.key,
          ),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
    final isUsable = thumb.isNotEmpty &&
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
      child: const Icon(Icons.play_circle_fill_rounded,
          color: Colors.white, size: 24),
    );
  }

  // ──────────────────────────────────────
  //  Search Results
  // ──────────────────────────────────────

  Widget _buildSearchResults(YouTubeProvider provider, bool isDark) {
    if (provider.isLoading || (provider.isSearching && provider.searchResults.isEmpty)) {
      return const Center(child: LottieLoadingWidget.medium());
    }

    if (provider.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 56, color: AppColors.grey400),
            const SizedBox(height: 12),
            Text(
              provider.error != null
                  ? _localizedApiError(provider.error!)
                  : 'youtube.noVideos'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.grey500, fontSize: 15, height: 1.4),
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
                  const Icon(Icons.subscriptions_rounded,
                      size: 18, color: AppColors.primary),
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
                          horizontal: 10, vertical: 4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
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
                  child: _buildVideoCard(
                      provider.searchResults[index], isDark),
                );
              },
              childCount: provider.searchResults.length + 1,
            ),
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
                      left: Radius.circular(16)),
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
                              color: AppColors.primary
                                  .withValues(alpha: 0.08)),
                          errorWidget: (_, __, ___) => Container(
                            color:
                                AppColors.primary.withValues(alpha: 0.08),
                            child: const Icon(Icons.play_circle_outline,
                                size: 32, color: AppColors.primary),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.35)
                              ],
                            ),
                          ),
                        ),
                        const Center(
                          child: Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white, size: 30),
                        ),
                        if (video.cefrLevel.isNotEmpty)
                          Positioned(
                            top: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
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
  //  Saved Tab
  // ──────────────────────────────────────

  Widget _buildSavedTab(bool isDark) {
    return Consumer<YouTubeProvider>(
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
                  color: isDark ? Colors.white24 : AppColors.grey300,
                ),
                const SizedBox(height: 12),
                Text(
                  'Chưa có video nào được lưu',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : AppColors.textGrey,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Nhấn  trên thẻ video để lưu lại',
                  style: TextStyle(
                    color: isDark ? Colors.white24 : AppColors.grey400,
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
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) =>
              _buildSavedVideoCard(saved[index], isDark, provider),
        );
      },
    );
  }

  Widget _buildSavedVideoCard(
      SavedVideo saved, bool isDark, YouTubeProvider provider) {
    return GestureDetector(
      onTap: () {
        final video = YouTubeVideo(
          videoId: saved.videoId,
          title: saved.title,
          description: '',
          channelTitle: saved.channelTitle,
          channelId: '',
          publishedAt: '',
          thumbnailUrl: saved.thumbnailUrl,
          cefrLevel: saved.cefrLevel,
        );
        Navigator.pushNamed(context, '/youtube/player', arguments: video);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
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
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(16)),
              child: SizedBox(
                width: 120,
                height: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: saved.thumbnailUrl.isNotEmpty
                          ? saved.thumbnailUrl
                          : 'https://img.youtube.com/vi/${saved.videoId}/mqdefault.jpg',
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppColors.primary.withValues(alpha: 0.08)),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        child: const Icon(Icons.play_circle_outline,
                            size: 32, color: AppColors.primary),
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
                      child: Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 30),
                    ),
                    if (saved.cefrLevel.isNotEmpty)
                      Positioned(
                        top: 5,
                        left: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: _cefrColor(saved.cefrLevel),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            saved.cefrLevel,
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
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      saved.title,
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
                      saved.channelTitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Đã lưu ${_timeAgo(saved.savedAt)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white24 : AppColors.grey400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              onPressed: () => provider.unsaveVideo(saved.videoId),
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    if (diff.inDays < 30) return '${diff.inDays} ngày trước';
    return '${diff.inDays ~/ 30} tháng trước';
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
      case 'UCHaHD477h-FeBbrgBrwTDpA':
        return [const Color(0xFF1565C0), const Color(0xFF42A5F5)];
      case 'UCsooa4yRKGN_zEE8iknghZA':
        return [const Color(0xFF7C4DFF), const Color(0xFF536DFE)];
      case 'UCz4tgANd4yy8Oe0iXCdSWfA':
        return [const Color(0xFF00897B), const Color(0xFF26C6DA)];
      case 'UCVBErcpqaokOf4fI5j73K_w':
        return [const Color(0xFFEF6C00), const Color(0xFFFFCA28)];
      case 'UCvn_XCl_mgQmt3sD753MZ0Q':
        return [const Color(0xFFE91E63), const Color(0xFFFF5252)];
      case 'UCkowKaGPT_yWCebvqN0wBmA':
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
//  Category Info record
// ──────────────────────────────────────

class _CategoryInfo {
  final String label;
  final IconData icon;
  final Color color;
  final String key;

  const _CategoryInfo(this.label, this.icon, this.color, this.key);
}
