import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/network/api_config.dart';
import '../../../../core/widgets/cefr_badge.dart';
import '../../../../core/widgets/content_kit.dart';
import '../../domain/entities/youtube_entities.dart';

/// YouTube thumbnails are blocked by CORS on web, so they go through the
/// backend image proxy; already-proxied and empty URLs pass through.
String youTubeProxiedUrl(String url) {
  if (url.isEmpty) return '';
  if (url.startsWith('http') && !url.contains('/podcasts/proxy/')) {
    return '${ApiConfig.baseUrl}/podcasts/proxy/image?url=${Uri.encodeComponent(url)}';
  }
  return url;
}

String _thumbnailOf(YouTubeVideo video) => youTubeProxiedUrl(
  video.thumbnailUrl.isNotEmpty
      ? video.thumbnailUrl
      : 'https://img.youtube.com/vi/${video.videoId}/mqdefault.jpg',
);

/// 16:9 frame with a play mark and the video's CEFR level.
class YouTubeThumbnail extends StatelessWidget {
  final YouTubeVideo video;

  const YouTubeThumbnail({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final blank = ColoredBox(color: primary.withValues(alpha: 0.12));
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: _thumbnailOf(video),
          fit: BoxFit.cover,
          placeholder: (_, _) => blank,
          errorWidget: (_, _, _) => blank,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x59000000)],
            ),
          ),
        ),
        const Center(
          child: Icon(
            PhosphorIconsFill.playCircle,
            color: Color(0xE6FFFFFF),
            size: 32,
          ),
        ),
        if (video.cefrLevel.isNotEmpty)
          Positioned(
            top: 6,
            left: 6,
            child: CefrBadge(
              level: video.cefrLevel,
              size: CefrBadgeSize.small,
              onColored: true,
            ),
          ),
      ],
    );
  }
}

/// A video as a row: thumbnail, title and channel, with save / open actions.
class YouTubeVideoTile extends StatelessWidget {
  final YouTubeVideo video;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;
  final VoidCallback onOpenExternal;
  final String saveLabel;
  final String openLabel;

  const YouTubeVideoTile({
    super.key,
    required this.video,
    required this.isSaved,
    required this.onTap,
    required this.onToggleSave,
    required this.onOpenExternal,
    required this.saveLabel,
    required this.openLabel,
  });

  static const _thumbWidth = 144.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
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
                  child: SizedBox(
                    width: _thumbWidth,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: YouTubeThumbnail(video: video),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          video.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: contentMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TileAction(
                      tooltip: saveLabel,
                      onPressed: onToggleSave,
                      icon: isSaved
                          ? PhosphorIconsFill.bookmarkSimple
                          : PhosphorIconsBold.bookmarkSimple,
                      color: isSaved ? scheme.primary : contentMuted(context),
                    ),
                    _TileAction(
                      tooltip: openLabel,
                      onPressed: onOpenExternal,
                      icon: PhosphorIconsBold.arrowSquareOut,
                      color: contentMuted(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final Color color;

  const _TileAction({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon, size: 20, color: color),
    style: IconButton.styleFrom(minimumSize: const Size.square(44)),
  );
}

/// A video as a card for horizontal shelves: big thumbnail over its title.
class YouTubeShelfCard extends StatelessWidget {
  final YouTubeVideo video;
  final VoidCallback onTap;

  const YouTubeShelfCard({super.key, required this.video, required this.onTap});

  static const width = 264.0;

  /// Height a shelf of these needs at the current text scale.
  static double rowHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return width * 9 / 16 +
        12 +
        scaler.scale(14) * 1.3 * 2 +
        4 +
        scaler.scale(12) * 1.3 +
        4;
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: SizedBox(
          width: width,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: YouTubeThumbnail(video: video),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    video.title,
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
                    video.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: contentMuted(context),
                    ),
                  ),
                ],
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A channel as a round avatar with a primary ring and its name underneath.
class YouTubeChannelAvatar extends StatelessWidget {
  final YouTubeChannel channel;
  final VoidCallback onTap;

  const YouTubeChannelAvatar({
    super.key,
    required this.channel,
    required this.onTap,
  });

  static const width = 88.0;
  static const _diameter = 72.0;

  /// Height a rail of these needs at the current text scale.
  static double rowHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return _diameter + 8 + scaler.scale(12) * 1.3 * 2 + 4;
  }

  /// Only proxied or YouTube-channel image URLs are known to load.
  bool get _hasImage =>
      channel.thumbnail.isNotEmpty &&
      (channel.thumbnail.contains('/podcasts/proxy/') ||
          channel.thumbnail.contains('/ytc/'));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = channel.name.isEmpty
        ? '?'
        : String.fromCharCode(channel.name.runes.first).toUpperCase();

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: SizedBox(
          width: width,
          child: Stack(
            children: [
              SizedBox(
                width: width,
                child: Column(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: ClipOval(
                          child: SizedBox.square(
                            dimension: _diameter - 10,
                            child: _hasImage
                                ? CachedNetworkImage(
                                    imageUrl: channel.thumbnail,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) =>
                                        _Initial(initial: initial),
                                  )
                                : _Initial(initial: initial),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      channel.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(_diameter / 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String initial;

  const _Initial({required this.initial});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
