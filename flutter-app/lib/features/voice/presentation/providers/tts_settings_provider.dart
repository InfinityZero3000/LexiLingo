import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TTS Settings Provider
/// Manages global TTS settings like playback speed
class TtsSettingsProvider extends ChangeNotifier {
  static const String _speedKey = 'tts_playback_speed';
  static const double defaultSpeed = 1.0;
  
  double _playbackSpeed = defaultSpeed;
  bool _isInitialized = false;

  /// Available speed options
  static const List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  
  /// Current playback speed
  double get playbackSpeed => _playbackSpeed;
  
  /// Whether settings have been loaded
  bool get isInitialized => _isInitialized;
  
  /// Get speed label for display
  String get speedLabel {
    if (_playbackSpeed == 1.0) return 'Normal';
    return '${_playbackSpeed}x';
  }

  /// Get icon for current speed
  String getSpeedIcon() {
    if (_playbackSpeed < 1.0) return '🐢';
    if (_playbackSpeed > 1.0) return '🐇';
    return '▶️';
  }

  /// Initialize from SharedPreferences
  Future<void> init() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _playbackSpeed = prefs.getDouble(_speedKey) ?? defaultSpeed;
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load TTS settings: $e');
      _isInitialized = true;
    }
  }

  /// Set playback speed and persist
  Future<void> setPlaybackSpeed(double speed) async {
    if (!speedOptions.contains(speed)) return;
    if (_playbackSpeed == speed) return;
    
    _playbackSpeed = speed;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_speedKey, speed);
    } catch (e) {
      debugPrint('Failed to save TTS speed: $e');
    }
  }

  /// Cycle to next speed option
  Future<void> cycleSpeed() async {
    final currentIndex = speedOptions.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % speedOptions.length;
    await setPlaybackSpeed(speedOptions[nextIndex]);
  }

  /// Reset to default speed
  Future<void> resetSpeed() async {
    await setPlaybackSpeed(defaultSpeed);
  }
}
