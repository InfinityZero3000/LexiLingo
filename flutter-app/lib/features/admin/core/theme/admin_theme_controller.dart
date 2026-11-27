import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted theme mode controller for the embedded LexiLingo Admin panel.
/// Allows admins to switch between Light, Dark, and System backgrounds
/// independently of the learner app's default.
class AdminThemeController extends ChangeNotifier {
  static const String _prefKey = 'lexi_admin_theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      final parsed = _parse(raw);
      if (parsed != _mode) {
        _mode = parsed;
        notifyListeners();
      }
    } catch (_) {
      // Fall back to default light mode if prefs are unavailable (e.g. tests).
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {
      // Ignore persistence failures in ephemeral environments.
    }
  }

  /// Toggles between Light and Dark based on the currently resolved brightness.
  Future<void> toggle(Brightness currentBrightness) {
    final next = currentBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    return setMode(next);
  }

  static ThemeMode _parse(String? raw) {
    return switch (raw) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      'light' || _ => ThemeMode.light,
    };
  }
}
