import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/widgets/content_kit.dart';

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
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration?> onSleepTimerSet;
  final bool isPlaying;
  final double playbackSpeed;
  final Duration position;
  final Duration duration;
  final String episodeTitle;
  final String artworkUrl;
  final int? sleepTimerSecondsRemaining;

  const AudioPlayerControls({
    super.key,
    required this.onPlay,
    required this.onPause,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onSpeedChange,
    required this.onSeek,
    required this.onSleepTimerSet,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.position,
    required this.duration,
    required this.episodeTitle,
    required this.artworkUrl,
    this.sleepTimerSecondsRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final muted = contentMuted(context);
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Seek bar ──
            Semantics(
              label: episodeTitle,
              child: _SeekBar(
                progress: progress.toDouble(),
                duration: duration,
                onSeek: onSeek,
              ),
            ),

            // ── Time labels ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Playback controls ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SpeedButton(
                  speed: playbackSpeed,
                  onTap: () => _showSpeedSheet(context),
                ),
                IconButton(
                  onPressed: onSkipBack,
                  icon: const Icon(Icons.fast_rewind_rounded),
                  iconSize: 32,
                  color: scheme.onSurface,
                  tooltip: 'podcast.rewind15'.tr(),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: isPlaying ? onPause : onPlay,
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 36,
                      color: scheme.onPrimary,
                    ),
                    tooltip: isPlaying
                        ? 'podcast.pause'.tr()
                        : 'podcast.play'.tr(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(64),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onSkipForward,
                  icon: const Icon(Icons.fast_forward_rounded),
                  iconSize: 32,
                  color: scheme.onSurface,
                  tooltip: 'podcast.forward15'.tr(),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                  ),
                ),
                _SleepTimerButton(
                  secondsRemaining: sleepTimerSecondsRemaining,
                  onTap: () => _showSleepTimerSheet(context),
                ),
              ],
            ),
          ],
        ),
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
                      s == 1.0 ? '1.0× · ${'podcast.speedNormal'.tr()}' : '$s×',
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary,
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
  //  Sleep timer bottom sheet
  // ──────────────────────────────────────

  void _showSleepTimerSheet(BuildContext context) {
    const presetMinutes = [5, 15, 30, 45, 60];
    final isActive = sleepTimerSecondsRemaining != null;
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
                    'podcast.sleepTimer'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isActive)
                  ListTile(
                    leading: Icon(
                      Icons.bedtime_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      'podcast.sleepTimerCancel'.tr(
                        namedArgs: {
                          'count':
                              '${((sleepTimerSecondsRemaining ?? 0) / 60).ceil()}',
                        },
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    onTap: () {
                      onSleepTimerSet(null);
                      Navigator.pop(context);
                    },
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.bedtime_outlined),
                    title: Text('podcast.sleepTimerOff'.tr()),
                    onTap: () => Navigator.pop(context),
                  ),
                ...presetMinutes.map((minutes) {
                  return ListTile(
                    leading: const Icon(Icons.bedtime_outlined),
                    title: Text(
                      'podcast.sleepTimerMinutes'.tr(
                        namedArgs: {'count': '$minutes'},
                      ),
                    ),
                    onTap: () {
                      onSleepTimerSet(Duration(minutes: minutes));
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

class _SeekBar extends StatefulWidget {
  final double progress; // 0.0 – 1.0, from the live position stream
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const _SeekBar({
    required this.progress,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  // Non-null only while the user's thumb is down — while dragging, the
  // displayed value must follow the drag, not the live position stream,
  // or the two fight for control of the thumb.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = (_dragValue ?? widget.progress).clamp(0.0, 1.0);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
        thumbColor: scheme.primary,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      child: Slider(
        value: value,
        onChanged: (v) => setState(() => _dragValue = v),
        onChangeEnd: (v) {
          final ms = (v * widget.duration.inMilliseconds).round();
          widget.onSeek(Duration(milliseconds: ms));
          setState(() => _dragValue = null);
        },
      ),
    );
  }
}

class _SleepTimerButton extends StatelessWidget {
  final int? secondsRemaining;
  final VoidCallback onTap;

  const _SleepTimerButton({
    required this.secondsRemaining,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = secondsRemaining != null;
    return IconButton(
      onPressed: onTap,
      icon: Icon(isActive ? Icons.bedtime_rounded : Icons.bedtime_outlined),
      iconSize: 24,
      color: isActive ? scheme.primary : scheme.onSurface,
      tooltip: 'podcast.sleepTimer'.tr(),
      style: IconButton.styleFrom(minimumSize: const Size.square(48)),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  final double speed;
  final VoidCallback onTap;

  const _SpeedButton({required this.speed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'podcast.playbackSpeed'.tr(),
      child: SizedBox(
        height: 44,
        child: Material(
          color: scheme.primary.withValues(alpha: 0.12),
          shape: StadiumBorder(
            side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  '$speed×',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
