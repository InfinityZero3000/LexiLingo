import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/user/domain/entities/settings.dart';
import 'package:lexilingo_app/features/user/domain/repositories/settings_repository.dart';

/// Provider for managing user settings
class SettingsProvider extends ChangeNotifier {
  final SettingsRepository _repository;
  
  Settings? _settings;
  bool _isLoading = false;
  String? _error;

  SettingsProvider({required SettingsRepository repository})
      : _repository = repository;

  Settings? get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Default values
  String get language => _settings?.language ?? 'en';
  int get dailyGoalXP => _settings?.dailyGoalXP ?? 50;
  String get theme => _settings?.theme ?? 'system';
  bool get notificationEnabled => _settings?.notificationEnabled ?? true;
  String get notificationTime => _settings?.notificationTime ?? '09:00';
  bool get soundEnabled => _settings?.soundEnabled ?? true;

  /// Available languages
  static const List<Map<String, String>> availableLanguages = [
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
    {'code': 'vi', 'name': 'Tiếng Việt', 'flag': '🇻🇳'},
    {'code': 'ja', 'name': '日本語', 'flag': '🇯🇵'},
    {'code': 'ko', 'name': '한국어', 'flag': '🇰🇷'},
    {'code': 'zh', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
  ];

  /// Daily goal presets
  static const List<Map<String, dynamic>> dailyGoalPresets = [
    {'xp': 10, 'label': 'Casual', 'description': '5 minutes/day', 'icon': '🌱'},
    {'xp': 30, 'label': 'Regular', 'description': '10 minutes/day', 'icon': '📚'},
    {'xp': 50, 'label': 'Serious', 'description': '15 minutes/day', 'icon': '🔥'},
    {'xp': 100, 'label': 'Intense', 'description': '30 minutes/day', 'icon': '💪'},
    {'xp': 200, 'label': 'Insane', 'description': '1 hour/day', 'icon': '🏆'},
  ];

  /// Load settings for user
  Future<void> loadSettings(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.getSettings(userId);
      result.fold(
        (failure) {
          _error = failure.message;
          // Create default settings if not found
          _settings = Settings(
            id: 0,
            userId: userId,
          );
        },
        (settings) {
          _settings = settings;
        },
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update language preference
  Future<void> updateLanguage(String languageCode) async {
    if (_settings == null) return;

    final oldLanguage = _settings!.language;
    _settings = _settings!.copyWith(language: languageCode);
    notifyListeners();

    try {
      final result = await _repository.updateSettings(_settings!);
      result.fold(
        (failure) {
          // Revert on failure
          _settings = _settings!.copyWith(language: oldLanguage);
          _error = failure.message;
          notifyListeners();
        },
        (_) {
          _error = null;
        },
      );
    } catch (e) {
      _settings = _settings!.copyWith(language: oldLanguage);
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Update daily goal XP
  Future<void> updateDailyGoal(int xp) async {
    if (_settings == null) return;

    final oldGoal = _settings!.dailyGoalXP;
    _settings = _settings!.copyWith(dailyGoalXP: xp);
    notifyListeners();

    try {
      final result = await _repository.updateDailyGoalXP(_settings!.userId, xp);
      result.fold(
        (failure) {
          _settings = _settings!.copyWith(dailyGoalXP: oldGoal);
          _error = failure.message;
          notifyListeners();
        },
        (_) {
          _error = null;
        },
      );
    } catch (e) {
      _settings = _settings!.copyWith(dailyGoalXP: oldGoal);
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Update theme preference
  Future<void> updateTheme(String theme) async {
    if (_settings == null) return;

    final oldTheme = _settings!.theme;
    _settings = _settings!.copyWith(theme: theme);
    notifyListeners();

    try {
      final result = await _repository.updateSettings(_settings!);
      result.fold(
        (failure) {
          _settings = _settings!.copyWith(theme: oldTheme);
          _error = failure.message;
          notifyListeners();
        },
        (_) {
          _error = null;
        },
      );
    } catch (e) {
      _settings = _settings!.copyWith(theme: oldTheme);
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Update notification settings
  Future<void> updateNotificationSettings({
    bool? enabled,
    String? time,
  }) async {
    if (_settings == null) return;

    final oldEnabled = _settings!.notificationEnabled;
    final oldTime = _settings!.notificationTime;
    
    _settings = _settings!.copyWith(
      notificationEnabled: enabled ?? oldEnabled,
      notificationTime: time ?? oldTime,
    );
    notifyListeners();

    try {
      final result = await _repository.updateSettings(_settings!);
      result.fold(
        (failure) {
          _settings = _settings!.copyWith(
            notificationEnabled: oldEnabled,
            notificationTime: oldTime,
          );
          _error = failure.message;
          notifyListeners();
        },
        (_) {
          _error = null;
        },
      );
    } catch (e) {
      _settings = _settings!.copyWith(
        notificationEnabled: oldEnabled,
        notificationTime: oldTime,
      );
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Update sound setting
  Future<void> updateSoundEnabled(bool enabled) async {
    if (_settings == null) return;

    final oldEnabled = _settings!.soundEnabled;
    _settings = _settings!.copyWith(soundEnabled: enabled);
    notifyListeners();

    try {
      final result = await _repository.updateSettings(_settings!);
      result.fold(
        (failure) {
          _settings = _settings!.copyWith(soundEnabled: oldEnabled);
          _error = failure.message;
          notifyListeners();
        },
        (_) {
          _error = null;
        },
      );
    } catch (e) {
      _settings = _settings!.copyWith(soundEnabled: oldEnabled);
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Get current language name
  String get currentLanguageName {
    final lang = availableLanguages.firstWhere(
      (l) => l['code'] == language,
      orElse: () => availableLanguages.first,
    );
    return lang['name'] ?? 'English';
  }

  /// Get current language flag
  String get currentLanguageFlag {
    final lang = availableLanguages.firstWhere(
      (l) => l['code'] == language,
      orElse: () => availableLanguages.first,
    );
    return lang['flag'] ?? '🇺🇸';
  }

  /// Get current goal label
  String get currentGoalLabel {
    final goal = dailyGoalPresets.firstWhere(
      (g) => g['xp'] == dailyGoalXP,
      orElse: () => dailyGoalPresets[2], // Default to "Serious"
    );
    return goal['label'] as String;
  }

  /// Get current goal icon
  String get currentGoalIcon {
    final goal = dailyGoalPresets.firstWhere(
      (g) => g['xp'] == dailyGoalXP,
      orElse: () => dailyGoalPresets[2],
    );
    return goal['icon'] as String;
  }
}
