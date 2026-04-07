import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/podcast_entities.dart';

/// Compact podcast card for list/grid display.
///
/// Shows artwork, title, author, CEFR badge, episode count, and follow button.
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(podcast.cefrLevel);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Artwork ──
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Stack(
                children: [
                  // Artwork image
                  SizedBox(
                    width: 160,
                    height: 140,
                    child: podcast.artworkUrl.isNotEmpty
                        ? Image.network(
                            podcast.artworkUrl,
                            width: 160,
                            height: 140,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildArtworkFallback(cefrColor),
                          )
                        : _buildArtworkFallback(cefrColor),
                  ),
                  // CEFR badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildCefrBadge(podcast.cefrLevel, cefrColor),
                  ),
                  // Follow indicator dot
                  if (isFollowed)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.greenSuccess,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Info ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    podcast.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Author
                  Text(
                    podcast.author,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : AppColors.textGrey,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Episode count row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.podcasts_rounded,
                            size: 12,
                            color: isDark ? Colors.white38 : AppColors.textGrey,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${podcast.episodeCount} eps',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white38
                                  : AppColors.textGrey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      // Follow button
                      GestureDetector(
                        onTap: onTap,
                        child: Icon(
                          isFollowed
                              ? Icons.check_circle_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 20,
                          color: isFollowed
                              ? AppColors.greenSuccess
                              : cefrColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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

  Widget _buildArtworkFallback(Color color) {
    return Container(
      width: 160,
      height: 140,
      color: color.withValues(alpha: 0.12),
      child: Icon(Icons.podcasts_rounded, size: 48, color: color),
    );
  }

  Widget _buildCefrBadge(String level, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        level,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
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
