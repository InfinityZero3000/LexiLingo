import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Full-width list tile for a single podcast episode.
///
/// Shows episode number, title, duration, published date, CEFR badge,
/// a download state button, and a listen-progress indicator.
///
/// [onDownload] is called when the user taps the download button while the
/// episode is in [DownloadState.notDownloaded]. Pass `null` to disable the
/// interactive download button (e.g., while loading).
///
/// Phase 4: Podcast.
class EpisodeTile extends StatelessWidget {
  final PodcastEpisode episode;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  const EpisodeTile({
    super.key,
    required this.episode,
    required this.onTap,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(episode.cefrLevel ?? 'B1');
    final totalSeconds = episode.durationSeconds;
    final progress = totalSeconds > 0
        ? (episode.listenProgress / totalSeconds).clamp(0.0, 1.0)
        : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Episode number badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cefrColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    episode.episodeNumber != null
                        ? '#${episode.episodeNumber}'
                        : '–',
                    style: TextStyle(
                      color: cefrColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Title + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        episode.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // Meta row: duration · date · CEFR
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Duration
                          _MetaChip(
                            icon: Icons.schedule_rounded,
                            label: _formatDuration(totalSeconds),
                            color: isDark ? Colors.white54 : AppColors.textGrey,
                          ),
                          // Published date
                          _MetaChip(
                            icon: Icons.calendar_today_rounded,
                            label: _relativeDate(episode.publishedAt),
                            color: isDark ? Colors.white54 : AppColors.textGrey,
                          ),
                          // CEFR badge
                          if (episode.cefrLevel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cefrColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                episode.cefrLevel!,
                                style: TextStyle(
                                  color: AppColors.surfaceLight,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Download button
                _DownloadButton(
                  state: episode.downloadState,
                  onDownload: onDownload,
                ),
              ],
            ),

            // ── Progress bar (only when listen progress > 0) ──
            if (episode.listenProgress > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.toDouble(),
                  minHeight: 3,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.grey200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    episode.isCompleted ? AppColors.greenSuccess : cefrColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                episode.isCompleted
                    ? 'Completed'
                    : '${(progress * 100).toStringAsFixed(0)}% listened',
                style: TextStyle(
                  fontSize: 10,
                  color: episode.isCompleted
                      ? AppColors.greenSuccess
                      : (isDark ? Colors.white38 : AppColors.textGrey),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '–';
    if (totalSeconds >= 3600) {
      final h = totalSeconds ~/ 3600;
      final m = (totalSeconds % 3600) ~/ 60;
      return '${h}h ${m}m';
    }
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _relativeDate(String publishedAt) {
    if (publishedAt.isEmpty) return '';
    try {
      final date = DateTime.parse(publishedAt);
      final diff = DateTime.now().difference(date);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
      if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo ago';
      return '${diff.inDays ~/ 365}y ago';
    } catch (_) {
      return publishedAt;
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
//  Private sub-widgets
// ──────────────────────────────────────

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final DownloadState state;
  final VoidCallback? onDownload;

  const _DownloadButton({required this.state, this.onDownload});

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case DownloadState.downloaded:
        return Icon(
          Icons.download_done_rounded,
          size: 22,
          color: AppColors.greenSuccess,
        );
      case DownloadState.downloading:
        return const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadState.notDownloaded:
        return GestureDetector(
          onTap: onDownload,
          child: Icon(
            Icons.download_outlined,
            size: 22,
            color: onDownload != null ? AppColors.primary : AppColors.textGrey,
          ),
        );
    }
  }
}
