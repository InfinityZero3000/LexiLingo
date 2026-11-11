import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/core/widgets/content_kit.dart';
import 'package:lexilingo_app/core/widgets/empty_state_widget.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/podcast_entities.dart';
import '../providers/podcast_provider.dart';
import '../widgets/podcast_card.dart';
import 'podcast_detail_screen.dart';
import 'podcast_player_screen.dart';

/// Main podcast browse screen.
///
/// Provides:
/// - Debounced search bar (500 ms) that shows results as a tile list
/// - Featured carousel, level filter chips, followed shelf and curated
///   shelves when not searching
/// - Loading + error states
///
/// Phase 4: Podcast.
class PodcastExploreScreen extends StatefulWidget {
  const PodcastExploreScreen({super.key});

  @override
  State<PodcastExploreScreen> createState() => _PodcastExploreScreenState();
}

class _PodcastExploreScreenState extends State<PodcastExploreScreen> {
  static const _maxFeatured = 5;

  final _searchController = TextEditingController();
  Timer? _debounce;
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PodcastProvider>();
      provider.loadCuratedPodcasts();
      provider.loadFollowedPodcasts();
      provider.loadContinueListening();
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
    setState(() {});

    if (query.isEmpty) {
      context.read<PodcastProvider>().clearSearch();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<PodcastProvider>().searchPodcasts(query);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<PodcastProvider>(
          builder: (context, provider, _) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              SliverToBoxAdapter(child: _buildSearchField(context)),
              ..._buildBody(context, provider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          AppBackButton(onPressed: () => Navigator.pop(context)),
          Expanded(
            child: Text(
              'podcast.pageTitle'.tr(),
              style: contentDisplay(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = contentMuted(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'podcast.searchHint'.tr(),
          hintStyle: TextStyle(color: muted, fontSize: 14),
          prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, color: muted),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 18),
                  onPressed: _clearSearch,
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

  List<Widget> _buildBody(BuildContext context, PodcastProvider provider) {
    final categories = provider.curatedCategories;

    if (provider.isLoading && categories.isEmpty) {
      return const [
        // Not hasScrollBody:false — that asks the child for its intrinsic
        // height, and LottieLoadingWidget's LayoutBuilder cannot answer.
        SliverFillRemaining(child: Center(child: LottieLoadingWidget.medium())),
      ];
    }

    if (provider.error != null && categories.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: PhosphorIconsBold.wifiSlash,
            iconSize: 48,
            title: 'podcast.failedToLoad'.tr(),
            actionLabel: 'podcast.retry'.tr(),
            onAction: () {
              provider.clearError();
              provider.loadCuratedPodcasts();
            },
          ),
        ),
      ];
    }

    if (_searchController.text.isNotEmpty) {
      return _buildSearchResults(provider);
    }

    if (categories.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: PhosphorIconsBold.headphones,
            iconSize: 48,
            title: 'podcast.noCuratedPodcasts'.tr(),
          ),
        ),
      ];
    }

    return _buildCurated(context, provider, categories);
  }

  // ──────────────────────────────────────
  //  Search results view
  // ──────────────────────────────────────

  List<Widget> _buildSearchResults(PodcastProvider provider) {
    if (provider.isSearching) {
      return const [
        // Not hasScrollBody:false — that asks the child for its intrinsic
        // height, and LottieLoadingWidget's LayoutBuilder cannot answer.
        SliverFillRemaining(child: Center(child: LottieLoadingWidget.medium())),
      ];
    }

    if (provider.searchResults.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            icon: PhosphorIconsBold.headphones,
            iconSize: 48,
            title: 'podcast.noResultsFound'.tr(),
            description: 'podcast.tryDifferentSearch'.tr(),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        sliver: SliverList.separated(
          itemCount: provider.searchResults.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final podcast = provider.searchResults[index];
            return _SearchResultTile(
              podcast: podcast,
              isFollowed: _isFollowed(provider, podcast.feedUrl),
              onTap: () => _openDetail(podcast),
            );
          },
        ),
      ),
    ];
  }

  // ──────────────────────────────────────
  //  Curated view
  // ──────────────────────────────────────

  List<Widget> _buildCurated(
    BuildContext context,
    PodcastProvider provider,
    List<PodcastCategory> categories,
  ) {
    final filter = _filter.clamp(0, categories.length);
    final visible = filter == 0 ? categories : [categories[filter - 1]];
    final followed = provider.followedPodcasts;
    final featured = _featured(categories);

    return [
      SliverToBoxAdapter(
        child: ContentCarousel(
          count: featured.length,
          height: ContentHero.heightOf(context),
          itemBuilder: (context, i) => ContentHero(
            imageUrl: featured[i].artworkUrl,
            eyebrow: 'podcast.featured'.tr(),
            title: featured[i].title,
            subtitle: featured[i].author,
            cta: ContentCta(
              label: 'podcast.listenNow'.tr(),
              icon: PhosphorIconsFill.play,
            ),
            onTap: () => _openDetail(featured[i]),
          ),
        ),
      ),
      if (categories.length > 1)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: ContentChipBar(
              labels: [
                'podcast.filterAll'.tr(),
                ...categories.map((c) => c.label),
              ],
              selected: filter,
              onSelected: (i) => setState(() => _filter = i),
            ),
          ),
        ),
      if (provider.continueListening.isNotEmpty && filter == 0) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: ContentSectionHeader(
              title: 'podcast.continueListening'.tr(),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: _ContinueTile.heightOf(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: provider.continueListening.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _ContinueTile(
                history: provider.continueListening[i],
                onTap: () => _resume(provider.continueListening[i]),
              ),
            ),
          ),
        ),
      ],
      if (followed.isNotEmpty && filter == 0) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: ContentSectionHeader(title: 'podcast.following'.tr()),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: _FollowedTile.heightOf(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: followed.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _FollowedTile(
                follow: followed[i],
                onTap: () =>
                    _openDetail(_resolveFollowed(categories, followed[i])),
              ),
            ),
          ),
        ),
      ],
      for (final category in visible) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: ContentSectionHeader(title: category.label),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: PodcastCard.rowHeight(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: category.podcasts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final podcast = category.podcasts[i];
                return PodcastCard(
                  podcast: podcast,
                  isFollowed: _isFollowed(provider, podcast.feedUrl),
                  onTap: () => _openDetail(podcast),
                );
              },
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 40)),
    ];
  }

  /// One lead podcast per shelf, so the carousel spans levels.
  List<Podcast> _featured(List<PodcastCategory> categories) {
    final seen = <String>{};
    return [
      for (final c in categories)
        if (c.podcasts.isNotEmpty && seen.add(c.podcasts.first.feedUrl))
          c.podcasts.first,
    ].take(_maxFeatured).toList();
  }

  bool _isFollowed(PodcastProvider provider, String feedUrl) =>
      provider.followedPodcasts.any((f) => f.feedUrl == feedUrl);

  Podcast _resolveFollowed(
    List<PodcastCategory> categories,
    UserPodcastFollow follow,
  ) {
    for (final c in categories) {
      for (final p in c.podcasts) {
        if (p.feedUrl == follow.feedUrl) return p;
      }
    }
    return Podcast(
      id: follow.feedUrl,
      title: follow.podcastTitle,
      feedUrl: follow.feedUrl,
      artworkUrl: follow.artworkUrl,
    );
  }

  // ──────────────────────────────────────
  //  Navigation
  // ──────────────────────────────────────

  Future<void> _openDetail(Podcast podcast) async {
    trackContentInteraction(
      itemType: 'podcast',
      itemId: podcast.id,
      action: 'open',
      topic: podcast.categories.isNotEmpty ? podcast.categories.first : null,
      source: 'podcast_explore',
    );
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PodcastDetailScreen(podcast: podcast)),
    );
    _refreshContinueListening();
  }

  Future<void> _resume(ListeningHistory history) async {
    final episode = history.episode;
    if (episode == null) return;
    trackContentInteraction(
      itemType: 'podcast_episode',
      itemId: episode.guid,
      action: 'resume',
      source: 'podcast_continue',
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PodcastPlayerScreen(
          episode: episode,
          artworkUrl: history.artworkUrl.isNotEmpty
              ? history.artworkUrl
              : episode.imageUrl ?? '',
          podcastTitle: history.podcastTitle,
        ),
      ),
    );
    _refreshContinueListening();
  }

  void _refreshContinueListening() {
    if (mounted) context.read<PodcastProvider>().loadContinueListening();
  }
}

// ──────────────────────────────────────
//  Continue-listening tile
// ──────────────────────────────────────

class _ContinueTile extends StatelessWidget {
  final ListeningHistory history;
  final VoidCallback onTap;

  const _ContinueTile({required this.history, required this.onTap});

  static const _padding = 12.0;
  static const _cover = 64.0;

  static double heightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final text =
        scaler.scale(14) * 1.3 * 2 +
        4 +
        scaler.scale(12) * 1.3 * 2 +
        8 +
        4 +
        4 +
        4;
    return (text + _padding * 2).clamp(_cover + _padding * 2, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = contentMuted(context);
    final left = history.minutesLeft;
    final title = history.episode?.title ?? '';
    final artwork = history.artworkUrl.isNotEmpty
        ? history.artworkUrl
        : history.episode?.imageUrl ?? '';

    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: 'podcast.resume'.tr(),
        child: SizedBox(
          width: 304,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(_padding),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox.square(
                          dimension: _cover,
                          child: ContentImage(url: artwork),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              history.podcastTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: history.progress,
                                minHeight: 4,
                                color: scheme.primary,
                                backgroundColor: scheme.onSurface.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                            if (left != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'podcast.minutesLeft'.tr(
                                  namedArgs: {'count': '$left'},
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(
                          dimension: 44,
                          child: Icon(
                            PhosphorIconsFill.play,
                            size: 18,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────
//  Followed shelf tile
// ──────────────────────────────────────

class _FollowedTile extends StatelessWidget {
  final UserPodcastFollow follow;
  final VoidCallback onTap;

  const _FollowedTile({required this.follow, required this.onTap});

  static double heightOf(BuildContext context) {
    final lines = MediaQuery.textScalerOf(context).scale(14) * 1.3 * 2;
    return (lines + 24).clamp(80.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: SizedBox(
          width: 280,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox.square(
                          dimension: 56,
                          child: ContentImage(url: follow.artworkUrl),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          follow.podcastTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                      Icon(
                        PhosphorIconsBold.caretRight,
                        size: 16,
                        color: contentMuted(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    final scheme = Theme.of(context).colorScheme;

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox.square(
                        dimension: 64,
                        child: ContentImage(url: podcast.artworkUrl),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            podcast.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            podcast.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: contentMuted(context),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              CefrBadge(
                                level: podcast.cefrLevel,
                                size: CefrBadgeSize.small,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'podcast.episodeCount'.tr(
                                    namedArgs: {
                                      'count': '${podcast.episodeCount}',
                                    },
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: contentMuted(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isFollowed
                          ? PhosphorIconsFill.checkCircle
                          : PhosphorIconsBold.caretRight,
                      size: isFollowed ? 24 : 16,
                      color: isFollowed
                          ? scheme.primary
                          : contentMuted(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
