import 'package:flutter/material.dart';

import '../../../../core/widgets/cefr_badge.dart';
import '../../../../core/widgets/content_kit.dart';

/// The "now playing" head of the player: the artwork on a blurred copy of
/// itself, then the episode and show names. Everything on it is white — the
/// backdrop's scrim guarantees the contrast.
class PlayerHeader extends StatelessWidget {
  final String title;
  final String podcastTitle;
  final String artworkUrl;
  final String level;

  const PlayerHeader({
    super.key,
    required this.title,
    required this.podcastTitle,
    required this.artworkUrl,
    required this.level,
  });

  static const _maxArtwork = 280.0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final width = MediaQuery.sizeOf(context).width;
    final artwork = (width - 96).clamp(160.0, _maxArtwork);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Stack(
        children: [
          Positioned.fill(
            child: ContentBackdrop(
              url: artworkUrl,
              fallback: ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, top + 8, 24, 28),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: SizedBox.square(
                        dimension: artwork,
                        child: ContentImage(url: artworkUrl),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: contentDisplay(
                      context,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  if (podcastTitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      podcastTitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  CefrBadge(
                    level: level,
                    size: CefrBadgeSize.medium,
                    onColored: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
