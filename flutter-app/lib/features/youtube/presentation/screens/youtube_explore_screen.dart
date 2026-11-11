import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/widgets/content_kit.dart';
import 'package:lexilingo_app/core/widgets/empty_state_widget.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/youtube_entities.dart';
import '../providers/youtube_provider.dart';
import '../widgets/youtube_video_tiles.dart';

/// YouTube explore screen: a hero of recommended videos, topic chips, channel
/// avatars and a shelf, plus tabs for recommended / saved / history.
class YouTubeExploreScreen extends StatefulWidget {
  const YouTubeExploreScreen({super.key});

  @override
  State<YouTubeExploreScreen> createState() => _YouTubeExploreScreenState();
}

class _YouTubeExploreScreenState extends State<YouTubeExploreScreen>
    with SingleTickerProviderStateMixin {
  static const _maxHero = 4;
  static const _savedTabIndex = 2;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  late final YouTubeProvider _youtubeProvider;
  late final TabController _tabController;
  int _categoryIndex = 0;

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

  void _openVideo(YouTubeVideo video) {
    trackContentInteraction(
      itemType: 'video',
      itemId: video.videoId,
      action: 'open',
      source: 'youtube_explore',
    );
    Navigator.pushNamed(context, '/youtube/player', arguments: video);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildSearchField(context),
              Expanded(
                child: Consumer<YouTubeProvider>(
                  builder: (context, provider, _) {
                    if (provider.searchQuery.isNotEmpty) {
                      return _buildSearchResults(provider);
                    }
                    return Column(
                      children: [
                        _buildTabBar(context),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildHome(provider),
                              _buildRecommendationsTab(provider),
                              _buildSavedTab(provider),
                              _buildHistoryTab(provider),
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
  //  Header, search, tabs
  // ──────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          AppBackButton(onPressed: _onBackPressed),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'youtube.exploreTitle'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: contentDisplay(context),
                ),
                Text(
                  'youtube.learnThroughVideo'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: contentMuted(context)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showGuideDialog,
            tooltip: 'youtube.guideTitle'.tr(),
            style: IconButton.styleFrom(minimumSize: const Size.square(48)),
            icon: const Icon(PhosphorIconsBold.question),
          ),
          Consumer<YouTubeProvider>(
            builder: (context, provider, _) {
              final count = provider.savedVideos.length;
              return IconButton(
                onPressed: () {
                  if (_youtubeProvider.searchQuery.isNotEmpty) {
                    _searchController.clear();
                    _youtubeProvider.clearSearch();
                  }
                  _tabController.animateTo(_savedTabIndex);
                },
                tooltip: 'youtube.tabSaved'.tr(),
                style: IconButton.styleFrom(minimumSize: const Size.square(48)),
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 9 ? '9+' : '$count'),
                  child: Icon(
                    count > 0
                        ? PhosphorIconsFill.bookmarkSimple
                        : PhosphorIconsBold.bookmarkSimple,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = contentMuted(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (q) {
          _onSearchChanged(q);
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'youtube.searchHint'.tr(),
          hintStyle: TextStyle(color: muted, fontSize: 14),
          prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, color: muted),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    context.read<YouTubeProvider>().clearSearch();
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: scheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TabBar(
      controller: _tabController,
      // Scrollable so each tab is as wide as its label: four equal quarters
      // clip a bold "Khám phá" (and longer words in other languages).
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: scheme.outlineVariant,
      indicatorColor: scheme.primary,
      indicatorWeight: 3,
      labelColor: scheme.primary,
      unselectedLabelColor: contentMuted(context),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      tabs: [
        Tab(text: 'youtube.tabExplore'.tr()),
        Tab(text: 'youtube.tabRecommended'.tr()),
        Tab(text: 'youtube.tabSaved'.tr()),
        Tab(text: 'youtube.tabHistory'.tr()),
      ],
    );
  }

  // ──────────────────────────────────────
  //  Home tab
  // ──────────────────────────────────────

  // Getter, not a const list: labels must be resolved after a locale switch.
  List<({String label, String? key})> get _categories => [
    (label: 'youtube.filterAll'.tr(), key: null),
    (label: 'youtube.catGeneral'.tr(), key: 'general'),
    (label: 'youtube.catPronunciation'.tr(), key: 'pronunciation'),
    (label: 'youtube.catAcademic'.tr(), key: 'academic'),
    (label: 'youtube.catNews'.tr(), key: 'news'),
  ];

  Widget _buildHome(YouTubeProvider provider) {
    if (provider.isLoading && provider.channels.isEmpty) {
      return const Center(child: LottieLoadingWidget.medium());
    }

    final recommended = provider.recommendedVideos;
    final hero = recommended.take(_maxHero).toList();
    final shelf = recommended.skip(_maxHero).toList();
    final categories = _categories;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (hero.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ContentCarousel(
                count: hero.length,
                height: ContentHero.heightOf(context),
                itemBuilder: (context, i) => ContentHero(
                  imageUrl: youTubeProxiedUrl(
                    hero[i].thumbnailUrl.isNotEmpty
                        ? hero[i].thumbnailUrl
                        : 'https://img.youtube.com/vi/${hero[i].videoId}/hqdefault.jpg',
                  ),
                  eyebrow: hero[i].channelTitle,
                  title: hero[i].title,
                  cta: ContentCta(
                    label: 'youtube.watchNow'.tr(),
                    icon: PhosphorIconsFill.play,
                  ),
                  onTap: () => _openVideo(hero[i]),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: ContentChipBar(
              labels: [for (final c in categories) c.label],
              selected: _categoryIndex,
              onSelected: (i) {
                setState(() => _categoryIndex = i);
                provider.loadChannels(category: categories[i].key);
              },
            ),
          ),
        ),
        if (provider.channels.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 12),
              child: ContentSectionHeader(title: 'youtube.channelsTitle'.tr()),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: YouTubeChannelAvatar.rowHeight(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: provider.channels.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final channel = provider.channels[i];
                  return YouTubeChannelAvatar(
                    channel: channel,
                    onTap: () => provider.loadChannelVideos(
                      channel.id,
                      channelName: channel.name,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (shelf.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 12),
              child: ContentSectionHeader(
                title: 'youtube.tabRecommended'.tr(),
                actionLabel: 'common.seeAll'.tr(),
                onAction: () => _tabController.animateTo(1),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: YouTubeShelfCard.rowHeight(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: shelf.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, i) => YouTubeShelfCard(
                  video: shelf[i],
                  onTap: () => _openVideo(shelf[i]),
                ),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  // ──────────────────────────────────────
  //  Video rows (search, recommended, saved, history)
  // ──────────────────────────────────────

  Widget _videoTile(YouTubeProvider provider, YouTubeVideo video) {
    final saved = provider.isVideoSaved(video.videoId);
    return YouTubeVideoTile(
      video: video,
      isSaved: saved,
      saveLabel: saved
          ? 'youtube.removedFromSaved'.tr()
          : 'youtube.saveVideo'.tr(),
      openLabel: 'youtube.openOnYoutube'.tr(),
      onTap: () => _openVideo(video),
      onToggleSave: () => saved
          ? provider.unsaveVideo(video.videoId)
          : provider.saveVideo(video),
      onOpenExternal: () => _shareVideo(video),
    );
  }

  Widget _videoList(YouTubeProvider provider, List<YouTubeVideo> videos) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: videos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _videoTile(provider, videos[i]),
    );
  }

  Widget _buildSearchResults(YouTubeProvider provider) {
    if (provider.isLoading ||
        (provider.isSearching && provider.searchResults.isEmpty)) {
      return const Center(child: LottieLoadingWidget.medium());
    }

    if (provider.searchResults.isEmpty) {
      return EmptyStateWidget(
        icon: PhosphorIconsBold.magnifyingGlass,
        iconSize: 48,
        title: provider.error != null
            ? _localizedApiError(provider.error!)
            : 'youtube.noVideos'.tr(),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (provider.activeChannelName.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      provider.activeChannelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      context.read<YouTubeProvider>().clearSearch();
                      setState(() {});
                    },
                    icon: const Icon(PhosphorIconsBold.arrowLeft, size: 16),
                    label: Text('common.back'.tr()),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          sliver: SliverList.separated(
            itemCount: provider.searchResults.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i >= provider.searchResults.length) {
                return provider.isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: LottieLoadingWidget.medium()),
                      )
                    : const SizedBox.shrink();
              }
              return _videoTile(provider, provider.searchResults[i]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationsTab(YouTubeProvider provider) {
    if (provider.isLoadingRecommendations) {
      return const Center(child: LottieLoadingWidget.medium());
    }
    final videos = provider.recommendedVideos;
    return RefreshIndicator(
      onRefresh: provider.loadRecommendations,
      child: videos.isEmpty
          ? _scrollableEmpty(
              EmptyStateWidget(
                icon: PhosphorIconsBold.sparkle,
                iconSize: 48,
                title: 'youtube.noRecommendations'.tr(),
                description: 'youtube.noRecommendationsDesc'.tr(),
                actionLabel: 'home.reload'.tr(),
                onAction: provider.loadRecommendations,
              ),
            )
          : _videoList(provider, videos),
    );
  }

  Widget _buildSavedTab(YouTubeProvider provider) {
    final saved = provider.savedVideos;
    if (saved.isEmpty) {
      return EmptyStateWidget(
        icon: PhosphorIconsBold.bookmarkSimple,
        iconSize: 48,
        title: 'youtube.noSavedVideos'.tr(),
        description: 'youtube.noSavedVideosDesc'.tr(),
      );
    }
    return _videoList(provider, [
      for (final s in saved)
        YouTubeVideo(
          videoId: s.videoId,
          title: s.title,
          description: '',
          channelTitle: s.channelTitle,
          channelId: '',
          publishedAt: '',
          thumbnailUrl: s.thumbnailUrl,
          cefrLevel: s.cefrLevel,
        ),
    ]);
  }

  Widget _buildHistoryTab(YouTubeProvider provider) {
    final history = provider.watchHistory;
    if (history.isEmpty) {
      return EmptyStateWidget(
        icon: PhosphorIconsBold.clockCounterClockwise,
        iconSize: 48,
        title: 'youtube.emptyHistory'.tr(),
        description: 'youtube.emptyHistoryDesc'.tr(),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showClearHistoryDialog(provider),
              icon: const Icon(PhosphorIconsBold.trash, size: 18),
              label: Text('chat.clearHistory'.tr()),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            ),
          ),
        ),
        Expanded(child: _videoList(provider, history)),
      ],
    );
  }

  /// Keeps pull-to-refresh working when the tab has nothing to scroll.
  Widget _scrollableEmpty(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: constraints.maxHeight, child: child),
    ),
  );

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  Future<void> _shareVideo(YouTubeVideo video) async {
    final url = Uri.parse('https://www.youtube.com/watch?v=${video.videoId}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _localizedApiError(String error) {
    if (error.contains('503') || error.contains('unavailable')) {
      return 'youtube.errServiceUnavailable'.tr();
    }
    if (error.contains('429') ||
        error.contains('quota') ||
        error.contains('exhausted')) {
      return 'youtube.errQuotaExceeded'.tr();
    }
    if (error.contains('504') || error.contains('timeout')) {
      return 'youtube.errTimeout'.tr();
    }
    if (error.contains('401') || error.contains('403')) {
      return 'youtube.errForbidden'.tr();
    }
    return 'youtube.errLoadFailed'.tr();
  }

  void _showClearHistoryDialog(YouTubeProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('youtube.clearHistoryTitle'.tr()),
        content: Text('youtube.clearHistoryConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              provider.clearWatchHistory();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
  }

  void _showGuideDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'youtube.guideTitle'.tr(),
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
                  'youtube.guideIntro'.tr(),
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
                  title: 'youtube.guideTip1'.tr(),
                  desc: 'youtube.guideTip1Desc'.tr(),
                  isDark: isDark,
                ),
                _buildGuideItem(
                  icon: Icons.bookmark_add_rounded,
                  color: Colors.green,
                  title: 'youtube.guideTip2'.tr(),
                  desc: 'youtube.guideTip2Desc'.tr(),
                  isDark: isDark,
                ),
                _buildGuideItem(
                  icon: Icons.repeat_rounded,
                  color: Colors.purple,
                  title: 'youtube.guideTip3'.tr(),
                  desc: 'youtube.guideTip3Desc'.tr(),
                  isDark: isDark,
                ),
                _buildGuideItem(
                  icon: Icons.history_edu_rounded,
                  color: Colors.orange,
                  title: 'youtube.guideTip4'.tr(),
                  desc: 'youtube.guideTip4Desc'.tr(),
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
                    child: Text(
                      'youtube.guideCta'.tr(),
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
}
