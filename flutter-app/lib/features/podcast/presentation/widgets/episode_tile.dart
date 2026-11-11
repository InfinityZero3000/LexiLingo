import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/widgets/cefr_badge.dart';
import '../../../../core/widgets/content_kit.dart';
import '../../../../core/widgets/lottie_loading_widget.dart';
import '../../domain/entities/podcast_entities.dart';

/// Full-width card for a single podcast episode: a play disc, the title,
/// length and age, and how far the learner got.
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

  /// "Today", "3d ago"… in the learner's language.
  static String ageLabel(String publishedAt, {DateTime? now}) {
    if (publishedAt.isEmpty) return '';
    final date = DateTime.tryParse(publishedAt);
    if (date == null) return publishedAt;
    final days = (now ?? DateTime.now()).difference(date).inDays;
    if (days <= 0) return 'podcast.today'.tr();
    if (days == 1) return 'podcast.yesterday'.tr();
    if (days < 7) return 'podcast.daysAgo'.tr(namedArgs: {'count': '$days'});
    if (days < 30) {
      return 'podcast.weeksAgo'.tr(namedArgs: {'count': '${days ~/ 7}'});
    }
    if (days < 365) {
      return 'podcast.monthsAgo'.tr(namedArgs: {'count': '${days ~/ 30}'});
    }
    return 'podcast.yearsAgo'.tr(namedArgs: {'count': '${days ~/ 365}'});
  }

  /// "04:30" or "1h 5m"; "–" when the length is unknown.
  static String durationLabel(int totalSeconds) {
    if (totalSeconds <= 0) return '–';
    if (totalSeconds >= 3600) {
      return '${totalSeconds ~/ 3600}h ${(totalSeconds % 3600) ~/ 60}m';
    }
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = contentMuted(context);
    final total = episode.durationSeconds;
    final progress = total > 0
        ? (episode.listenProgress / total).clamp(0.0, 1.0)
        : 0.0;
    final age = ageLabel(episode.publishedAt);
    final meta = [durationLabel(total), if (age.isNotEmpty) age].join(' · ');
    final level = episode.cefrLevel;

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
                    _PlayDisc(done: episode.isCompleted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            episode.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: muted,
                                  ),
                                ),
                              ),
                              if (level != null) ...[
                                const SizedBox(width: 8),
                                CefrBadge(
                                  level: level,
                                  size: CefrBadgeSize.small,
                                ),
                              ],
                            ],
                          ),
                          if (episode.listenProgress > 0 ||
                              episode.isCompleted) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: episode.isCompleted ? 1 : progress,
                                minHeight: 4,
                                color: scheme.primary,
                                backgroundColor: scheme.onSurface.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              episode.isCompleted
                                  ? 'podcast.completed'.tr()
                                  : 'podcast.percentListened'.tr(
                                      namedArgs: {
                                        'percent':
                                            '${(progress * 100).round()}',
                                      },
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
                    if (!kIsWeb)
                      _DownloadButton(
                        state: episode.downloadState,
                        onDownload: onDownload,
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

class _PlayDisc extends StatelessWidget {
  final bool done;

  const _PlayDisc({required this.done});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary.withValues(alpha: 0.14),
      ),
      child: SizedBox.square(
        dimension: 44,
        child: Icon(
          done ? PhosphorIconsBold.check : PhosphorIconsFill.play,
          size: 18,
          color: primary,
        ),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final DownloadState state;
  final VoidCallback? onDownload;

  const _DownloadButton({required this.state, this.onDownload});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (state) {
      case DownloadState.downloaded:
        return Tooltip(
          message: 'podcast.downloaded'.tr(),
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              PhosphorIconsFill.checkCircle,
              size: 22,
              color: scheme.primary,
            ),
          ),
        );
      case DownloadState.downloading:
        return Tooltip(
          message: 'podcast.downloading'.tr(),
          child: const SizedBox.square(
            dimension: 44,
            child: Center(child: LottieLoadingWidget.tiny()),
          ),
        );
      case DownloadState.notDownloaded:
        return IconButton(
          onPressed: onDownload,
          tooltip: 'podcast.download'.tr(),
          style: IconButton.styleFrom(minimumSize: const Size.square(44)),
          icon: Icon(
            PhosphorIconsBold.downloadSimple,
            size: 22,
            color: onDownload != null ? scheme.primary : contentMuted(context),
          ),
        );
    }
  }
}
