import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Plays short UI sound effects for learning interactions.
///
/// Call [setEnabled] whenever [SettingsProvider.soundEnabled] changes.
/// All play methods are fire-and-forget — errors are silently swallowed
/// so a missing asset or audio focus loss never breaks the UX.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  bool _enabled = true;

  final AudioPlayer _player = AudioPlayer();

  void setEnabled(bool enabled) => _enabled = enabled;

  Future<void> playCorrect() => _play('assets/sounds/correct.wav');
  Future<void> playWrong()   => _play('assets/sounds/wrong.wav');
  Future<void> playComplete()=> _play('assets/sounds/complete.wav');
  Future<void> playTap()     => _play('assets/sounds/tap.wav');

  Future<void> _play(String asset) async {
    if (!_enabled) return;
    if (kIsWeb) return; // just_audio asset loading unreliable on web
    try {
      await _player.stop();
      await _player.setAsset(asset);
      await _player.play();
    } catch (_) {
      // Swallow — audio failure must never crash the learning flow
    }
  }

  void dispose() => _player.dispose();
}
