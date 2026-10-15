import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_theme.dart';

/// Bottom-bar style audio player controls widget.
///
/// Shows a seek bar, play/pause, ±15 s skip buttons, time labels,
/// and a speed selector (0.75×–2.0×).
///
/// Phase 4: Podcast.
class AudioPlayerControls extends StatelessWidget {
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final ValueChanged<double> onSpeedChange;
  final bool isPlaying;
  final double playbackSpeed;
  final Duration position;
  final Duration duration;
  final String episodeTitle;
  final String artworkUrl;

  const AudioPlayerControls({
    super.key,
    required this.onPlay,
    required this.onPause,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onSpeedChange,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.position,
    required this.duration,
    required this.episodeTitle,
    required this.artworkUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Episode title ──
          Text(
            episodeTitle,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),

          // ── Seek bar ──
          _SeekBar(progress: progress.toDouble(), isDark: isDark),
          const SizedBox(height: 6),

          // ── Time labels ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : AppColors.textGrey,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : AppColors.textGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Playback controls ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Speed button
              _SpeedButton(
                speed: playbackSpeed,
                isDark: isDark,
                onTap: () => _showSpeedSheet(context),
              ),

              // Skip back 15 s
              IconButton(
                onPressed: onSkipBack,
                icon: const Icon(Icons.replay_10_rounded),
                iconSize: 32,
                color: isDark ? Colors.white70 : AppColors.textDark,
                tooltip: 'podcast.rewind15'.tr(),
              ),

              // Play/Pause
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: isPlaying ? onPause : onPlay,
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 30,
                    color: AppColors.surfaceLight,
                  ),
                  tooltip: isPlaying ? 'Pause' : 'Play',
                ),
              ),

              // Skip forward 15 s
              IconButton(
                onPressed: onSkipForward,
                icon: const Icon(Icons.forward_10_rounded),
                iconSize: 32,
                color: isDark ? Colors.white70 : AppColors.textDark,
                tooltip: 'podcast.forward15'.tr(),
              ),

              // Placeholder for balance (keeps play/pause centred)
              const SizedBox(width: 40),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Speed bottom sheet
  // ──────────────────────────────────────

  void _showSpeedSheet(BuildContext context) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'podcast.playbackSpeed'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                ...speeds.map((s) {
                  final isSelected = s == playbackSpeed;
                  return ListTile(
                    leading: const Icon(Icons.speed_rounded),
                    title: Text(
                      s == 1.0 ? '1.0× (Normal)' : '$s×',
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: isSelected ? AppColors.primary : null,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                    onTap: () {
                      onSpeedChange(s);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString()}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ──────────────────────────────────────
//  Private sub-widgets
// ──────────────────────────────────────

class _SeekBar extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  final bool isDark;

  const _SeekBar({required this.progress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 4,
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : AppColors.grey200,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  final double speed;
  final bool isDark;
  final VoidCallback onTap;

  const _SpeedButton({
    required this.speed,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          '$speed×',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
