import 'dart:async';

/// One-second-tick countdown used by the podcast sleep timer.
///
/// Plain Dart, no Flutter/plugin imports — kept separate from
/// [PodcastAudioHandler] so the countdown itself is unit-testable without
/// mocking the `just_audio`/`audio_service` plugin channels.
class SleepTimerCountdown {
  Timer? _timer;

  bool get isActive => _timer != null;

  /// Starts (replacing any running countdown). Calls [onTick] immediately
  /// with the starting second count, then every second after, and
  /// [onElapsed] exactly once when it reaches zero.
  void start({
    required Duration duration,
    required void Function(int secondsRemaining) onTick,
    required void Function() onElapsed,
  }) {
    cancel();
    var remaining = duration.inSeconds;
    onTick(remaining);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
        _timer = null;
        onElapsed();
      } else {
        onTick(remaining);
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
