import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/widgets/cefr_badge.dart';
import '../../../../core/widgets/content_kit.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/lottie_loading_widget.dart';
import '../../domain/entities/podcast_entities.dart';
import '../providers/podcast_provider.dart';
import '../widgets/episode_tile.dart';
import 'podcast_player_screen.dart';

/// Podcast detail screen: artwork over a blurred copy of itself, the actions
/// that matter (play the latest episode, follow) and the episode list.
///
/// Loads episodes on init via [PodcastProvider.loadEpisodes].
/// Supports follow/unfollow with SnackBar confirmation.
///
/// Phase 4: Podcast.
class PodcastDetailScreen extends StatefulWidget {
  final Podcast podcast;

  const PodcastDetailScreen({super.key, required this.podcast});

  @override
  State<PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends State<PodcastDetailScreen> {
  /// Scroll depth at which the bar turns from clear-over-artwork to solid.
  static const _collapseAt = 220.0;

  final _scrollController = ScrollController();
  bool _descriptionExpanded = false;
  bool _followLoading = false;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PodcastProvider>().loadEpisodes(widget.podcast);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed = _scrollController.offset > _collapseAt;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  Future<void> _toggleFollow() async {
    setState(() => _followLoading = true);
    try {
      await context.read<PodcastProvider>().toggleFollow(widget.podcast);
      if (!mounted) return;
      final isNowFollowed = context
          .read<PodcastProvider>()
          .followedPodcasts
          .any((f) => f.feedUrl == widget.podcast.feedUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNowFollowed
                ? 'podcast.followingSnack'.tr(
                    namedArgs: {'title': widget.podcast.title},
                  )
                : 'podcast.unfollowedSnack'.tr(
                    namedArgs: {'title': widget.podcast.title},
                  ),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<PodcastProvider>(
        builder: (context, provider, _) {
          final isFollowed = provider.followedPodcasts.any(
            (f) => f.feedUrl == widget.podcast.feedUrl,
          );
          final episodes = provider.currentEpisodes;
          final episodeCount = episodes.isNotEmpty
              ? episodes.length
              : widget.podcast.episodeCount;

          return Stack(
            children: [
              CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: _Header(
                      podcast: widget.podcast,
                      isFollowed: isFollowed,
                      followLoading: _followLoading,
                      expanded: _descriptionExpanded,
                      onToggleExpanded: () => setState(
                        () => _descriptionExpanded = !_descriptionExpanded,
                      ),
                      onToggleFollow: _toggleFollow,
                      onPlayLatest: episodes.isEmpty
                          ? null
                          : () => _openPlayer(episodes.first),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
                      child: ContentSectionHeader(
                        title: 'podcast.episodeCount'.tr(
                          namedArgs: {'count': '$episodeCount'},
                        ),
                      ),
                    ),
                  ),
                  ..._buildEpisodes(provider),
                ],
              ),
              ContentTopBar(title: widget.podcast.title, collapsed: _collapsed),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildEpisodes(PodcastProvider provider) {
    final episodes = provider.currentEpisodes;

    if (provider.isLoading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          sliver: SliverList.separated(
            itemCount: 5,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, _) => const _EpisodeSkeleton(),
          ),
        ),
      ];
    }

    if (provider.error != null && episodes.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyStateWidget(
            icon: PhosphorIconsBold.wifiSlash,
            iconSize: 48,
            title: 'podcast.failedToLoadEpisodes'.tr(),
            actionLabel: 'podcast.retry'.tr(),
            onAction: () => provider.loadEpisodes(widget.podcast),
          ),
        ),
      ];
    }

    if (episodes.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyStateWidget(
            icon: PhosphorIconsBold.headphones,
            iconSize: 48,
            title: 'podcast.noEpisodes'.tr(),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        sliver: SliverList.separated(
          itemCount: episodes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final ep = episodes[index];
            return EpisodeTile(
              episode: ep,
              onTap: () => _openPlayer(ep),
              onDownload: ep.downloadState == DownloadState.notDownloaded
                  ? () => provider.downloadEpisode(ep)
                  : null,
            );
          },
        ),
      ),
    ];
  }

  void _openPlayer(PodcastEpisode episode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PodcastPlayerScreen(
          episode: episode,
          artworkUrl: episode.imageUrl ?? widget.podcast.artworkUrl,
          podcastTitle: widget.podcast.title,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────
//  Header
// ──────────────────────────────────────

class _Header extends StatelessWidget {
  final Podcast podcast;
  final bool isFollowed;
  final bool followLoading;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleFollow;
  final VoidCallback? onPlayLatest;

  const _Header({
    required this.podcast,
    required this.isFollowed,
    required this.followLoading,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onToggleFollow,
    required this.onPlayLatest,
  });

  static const _artwork = 176.0;
  static const _onScrim = Color(0xE6FFFFFF);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 56;
    return Stack(
      children: [
        Positioned.fill(
          child: ContentBackdrop(
            url: podcast.artworkUrl,
            fallback: ColoredBox(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, top, 20, 24),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox.square(
                    dimension: _artwork,
                    child: ContentImage(url: podcast.artworkUrl),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                podcast.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: contentDisplay(context, color: Colors.white),
              ),
              if (podcast.author.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  podcast.author,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _onScrim, fontSize: 14),
                ),
              ],
              const SizedBox(height: 12),
              CefrBadge(
                level: podcast.cefrLevel,
                size: CefrBadgeSize.medium,
                onColored: true,
              ),
              const SizedBox(height: 20),
              _Actions(
                isFollowed: isFollowed,
                followLoading: followLoading,
                onToggleFollow: onToggleFollow,
                onPlayLatest: onPlayLatest,
              ),
              if (podcast.description.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Description(
                  text: podcast.description,
                  expanded: expanded,
                  onToggle: onToggleExpanded,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final bool isFollowed;
  final bool followLoading;
  final VoidCallback onToggleFollow;
  final VoidCallback? onPlayLatest;

  const _Actions({
    required this.isFollowed,
    required this.followLoading,
    required this.onToggleFollow,
    required this.onPlayLatest,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        if (onPlayLatest != null)
          Stack(
            children: [
              ContentCta(
                label: 'podcast.playLatest'.tr(),
                icon: PhosphorIconsFill.play,
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onPlayLatest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        OutlinedButton.icon(
          onPressed: followLoading ? null : onToggleFollow,
          icon: followLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: LottieLoadingWidget.tiny(),
                )
              : Icon(
                  isFollowed ? PhosphorIconsBold.check : PhosphorIconsBold.plus,
                  size: 18,
                ),
          label: Text(
            isFollowed ? 'podcast.following'.tr() : 'podcast.follow'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: const Color(0x99FFFFFF),
            side: const BorderSide(color: Color(0x99FFFFFF)),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ],
    );
  }
}

class _Description extends StatelessWidget {
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  const _Description({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: expanded ? null : 3,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(
            color: _Header._onScrim,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        TextButton(
          onPressed: onToggle,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 44),
          ),
          child: Text(
            expanded ? 'podcast.showLess'.tr() : 'podcast.showMore'.tr(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────
//  Skeleton
// ──────────────────────────────────────

class _EpisodeSkeleton extends StatelessWidget {
  const _EpisodeSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.onSurface.withValues(alpha: 0.08),
      highlightColor: scheme.onSurface.withValues(alpha: 0.16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const SizedBox(height: 80, width: double.infinity),
      ),
    );
  }
}
