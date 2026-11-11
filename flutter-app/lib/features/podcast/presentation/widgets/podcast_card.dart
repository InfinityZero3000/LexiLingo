import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/widgets/cefr_badge.dart';
import '../../../../core/widgets/content_kit.dart';
import '../../domain/entities/podcast_entities.dart';

/// Square cover with title and author underneath, for horizontal shelves.
///
/// Phase 4: Podcast.
class PodcastCard extends StatelessWidget {
  final Podcast podcast;
  final VoidCallback onTap;
  final bool isFollowed;

  const PodcastCard({
    super.key,
    required this.podcast,
    required this.onTap,
    required this.isFollowed,
  });

  static const coverSize = 148.0;
  static const _radius = 20.0;

  /// Height a shelf of these needs at the current text scale.
  static double rowHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return coverSize +
        12 +
        scaler.scale(14) * 1.3 * 2 +
        4 +
        scaler.scale(12) * 1.3 +
        4;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: SizedBox(
          width: coverSize,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(_radius),
                    child: SizedBox.square(
                      dimension: coverSize,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ContentImage(url: podcast.artworkUrl),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: CefrBadge(
                              level: podcast.cefrLevel,
                              size: CefrBadgeSize.small,
                              onColored: true,
                            ),
                          ),
                          if (isFollowed)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    PhosphorIconsBold.check,
                                    size: 12,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    podcast.title,
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
                    podcast.author,
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
                    borderRadius: BorderRadius.circular(_radius),
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
