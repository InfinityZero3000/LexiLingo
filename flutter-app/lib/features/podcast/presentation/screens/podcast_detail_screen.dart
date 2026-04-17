import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/podcast_entities.dart';
import '../providers/podcast_provider.dart';
import '../widgets/episode_tile.dart';
import 'podcast_player_screen.dart';

/// Podcast detail screen — shows podcast info + episode list.
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
  bool _descriptionExpanded = false;
  bool _followLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PodcastProvider>().loadEpisodes(widget.podcast);
    });
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
                ? 'Following "${widget.podcast.title}"'
                : 'Unfollowed "${widget.podcast.title}"',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(widget.podcast.cefrLevel);

    return Scaffold(
      body: Consumer<PodcastProvider>(
        builder: (context, provider, _) {
          final isFollowed = provider.followedPodcasts.any(
            (f) => f.feedUrl == widget.podcast.feedUrl,
          );
          final episodeCount = provider.currentEpisodes.isNotEmpty
              ? provider.currentEpisodes.length
              : widget.podcast.episodeCount;

          return CustomScrollView(
            slivers: [
              // ── SliverAppBar ──
              SliverAppBar(
                pinned: true,
                expandedHeight: 0,
                backgroundColor: isDark
                    ? AppColors.backgroundDark
                    : Colors.white,
                title: Text(
                  widget.podcast.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _followLoading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: LottieLoadingWidget.tiny(),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: _toggleFollow,
                            icon: Icon(
                              isFollowed
                                  ? Icons.check_rounded
                                  : Icons.add_rounded,
                              size: 18,
                            ),
                            label: Text(isFollowed ? 'Following' : 'Follow'),
                            style: TextButton.styleFrom(
                              foregroundColor: isFollowed
                                  ? AppColors.greenSuccess
                                  : AppColors.primary,
                            ),
                          ),
                  ),
                ],
              ),

              // ── Podcast header ──
              SliverToBoxAdapter(
                child: _buildHeader(
                  widget.podcast,
                  cefrColor,
                  isDark,
                  isFollowed,
                ),
              ),

              // ── Episode count heading ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.format_list_numbered_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$episodeCount Episodes',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Episode list ──
              if (provider.isLoading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, __) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildEpisodeSkeleton(isDark),
                      ),
                      childCount: 5,
                    ),
                  ),
                )
              else if (provider.error != null &&
                  provider.currentEpisodes.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: Colors.red.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load episodes',
                            style: TextStyle(color: AppColors.grey500),
                          ),
                          TextButton(
                            onPressed: () =>
                                provider.loadEpisodes(widget.podcast),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (provider.currentEpisodes.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No episodes available',
                      style: TextStyle(
                        color: isDark ? Colors.white38 : AppColors.grey400,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final ep = provider.currentEpisodes[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: EpisodeTile(
                          episode: ep,
                          onTap: () => _openPlayer(ep),
                          onDownload:
                              ep.downloadState == DownloadState.notDownloaded
                              ? () => provider.downloadEpisode(ep)
                              : null,
                        ),
                      );
                    }, childCount: provider.currentEpisodes.length),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────
  //  Podcast header
  // ──────────────────────────────────────

  Widget _buildHeader(
    Podcast podcast,
    Color cefrColor,
    bool isDark,
    bool isFollowed,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Artwork + info row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork 160×160
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: podcast.artworkUrl.isNotEmpty
                    ? Image.network(
                        podcast.artworkUrl,
                        width: 160,
                        height: 160,
                        fit: BoxFit.cover,
                      webHtmlElementStrategy: WebHtmlElementStrategy.never,
                        errorBuilder: (_, __, ___) =>
                            _buildArtworkFallback(cefrColor),
                      )
                    : _buildArtworkFallback(cefrColor),
              ),
              const SizedBox(width: 16),

              // Title, author, CEFR
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      podcast.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      podcast.author,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : AppColors.textGrey,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // CEFR badge
                    Container(
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
                        podcast.cefrLevel,
                        style: TextStyle(
                          color: AppColors.surfaceLight,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Description (collapsible)
          if (podcast.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              podcast.description,
              style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textGrey,
                fontSize: 13,
                height: 1.5,
              ),
              maxLines: _descriptionExpanded ? null : 3,
              overflow: _descriptionExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            GestureDetector(
              onTap: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _descriptionExpanded ? 'Show less' : 'Show more',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Skeleton shimmer
  // ──────────────────────────────────────

  Widget _buildEpisodeSkeleton(bool isDark) {
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.grey200;
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : AppColors.grey100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Navigation
  // ──────────────────────────────────────

  void _openPlayer(PodcastEpisode episode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PodcastPlayerScreen(
          episode: episode,
          artworkUrl: episode.imageUrl ?? widget.podcast.artworkUrl,
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  Widget _buildArtworkFallback(Color color) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.podcasts_rounded, size: 64, color: color),
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
