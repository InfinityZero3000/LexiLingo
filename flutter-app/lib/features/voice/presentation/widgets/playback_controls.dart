import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Playback Controls Widget
/// Controls for playing back synthesized audio
class PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final Duration? currentPosition;
  final Duration? totalDuration;
  final double playbackSpeed;
  final Function(double)? onSpeedChange;

  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.isLoading,
    required this.onPlay,
    required this.onStop,
    this.currentPosition,
    this.totalDuration,
    this.playbackSpeed = 1.0,
    this.onSpeedChange,
  });

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          if (totalDuration != null) ...[
            Row(
              children: [
                Text(
                  _formatDuration(currentPosition),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: LinearProgressIndicator(
                      value: totalDuration!.inMilliseconds > 0
                          ? (currentPosition?.inMilliseconds ?? 0) /
                              totalDuration!.inMilliseconds
                          : 0,
                      backgroundColor: AppColors.grey200,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ),
                Text(
                  _formatDuration(totalDuration),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Speed selector
              if (onSpeedChange != null) ...[
                _SpeedButton(
                  speed: playbackSpeed,
                  onTap: () {
                    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5];
                    final currentIndex = speeds.indexOf(playbackSpeed);
                    final nextIndex = (currentIndex + 1) % speeds.length;
                    onSpeedChange!(speeds[nextIndex]);
                  },
                ),
                const SizedBox(width: 24),
              ],

              // Play/Stop button
              GestureDetector(
                onTap: isLoading ? null : (isPlaying ? onStop : onPlay),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : Icon(
                          isPlaying ? Icons.stop : Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  final double speed;
  final VoidCallback onTap;

  const _SpeedButton({required this.speed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.grey200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${speed}x',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }
}
