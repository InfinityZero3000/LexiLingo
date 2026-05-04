import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/features/user/domain/entities/settings.dart';
import 'package:lexilingo_app/features/user/domain/repositories/settings_repository.dart';

/// Provider for managing user settings
class SettingsProvider extends ChangeNotifier {
  final SettingsRepository _repository;
  final NotificationService _notificationService;

  Settings? _settings;
  String? _activeUserId;
  bool _isLoading = false;
  String? _error;

  SettingsProvider({
    required SettingsRepository repository,
    required NotificationService notificationService,
  }) : _repository = repository,
       _notificationService = notificationService;

  Settings? get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Default values
  String get language => _settings?.language ?? 'en';
  int get dailyGoalXP => _settings?.dailyGoalXP ?? 50;
  String get theme => _normalizeTheme(_settings?.theme);
  bool get notificationEnabled => _settings?.notificationEnabled ?? true;
  String get notificationTime => _settings?.notificationTime ?? '09:00';
  bool get soundEnabled => _settings?.soundEnabled ?? true;

  /// Available languages for settings selection.
  /// Must match supported locales in EasyLocalization (assets/i18n/*.json)
  static const List<Map<String, String>> availableLanguages = [
    {'code': 'vi', 'name': 'Tiếng Việt'},
    {'code': 'en', 'name': 'English'},
    {'code': 'ja', 'name': '日本語'},
    {'code': 'ko', 'name': '한국어'},
    {'code': 'zh', 'name': '中文'},
    {'code': 'fr', 'name': 'Français'},
    {'code': 'es', 'name': 'Español'},
  ];

  /// Daily goal presets with IconData
  static final List<Map<String, dynamic>> dailyGoalPresets = [
    {
      'xp': 10,
      'label': 'settings.goal_casual_label',
      'description': 'settings.goal_casual_description',
      'icon': Icons.eco,
    },
    {
      'xp': 30,
      'label': 'settings.goal_regular_label',
      'description': 'settings.goal_regular_description',
      'icon': Icons.menu_book,
    },
    {
      'xp': 50,
      'label': 'settings.goal_serious_label',
      'description': 'settings.goal_serious_description',
      'icon': Icons.local_fire_department,
    },
    {
      'xp': 100,
      'label': 'settings.goal_intense_label',
      'description': 'settings.goal_intense_description',
      'icon': Icons.fitness_center,
    },
    {
      'xp': 200,
      'label': 'settings.goal_insane_label',
      'description': 'settings.goal_insane_description',
      'icon': Icons.emoji_events,
    },
  ];

  /// Load settings for user
  Future<void> loadSettings(String userId) async {
    _activeUserId = userId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Read the locally-saved locale before touching settings so we can honour
    // a language the user picked (e.g. on the welcome screen) even when the
    // stored settings still carry the entity default ('en').
    final savedLocale = await LocaleService.getSavedLocale();

    try {
      final result = await _repository.getSettings(userId);
      result.fold(
        (failure) {
          _error = failure.message;
          // Create default settings seeded with the locally-chosen locale.
          _settings = Settings(id: 0, userId: userId, language: savedLocale);
        },
        (settings) {
          // If the stored language is still the entity default ('en') but the
          // user has explicitly selected a different locale locally, honour
          // their local choice instead of overriding it.
          final effectiveLang =
              (settings.language == 'en' && savedLocale != 'en')
                  ? savedLocale
                  : settings.language;
          _settings = settings.copyWith(
            theme: _normalizeTheme(settings.theme),
            language: effectiveLang,
          );
        },
      );
    } catch (e) {
      _error = e.toString();
      // Keep settings usable even if cached payload is malformed.
      _settings = Settings(id: 0, userId: userId, language: savedLocale);
    } finally {
      _isLoading = false;
      notifyListeners();
      // Sync reminder asynchronously — must not block isLoading flag.
      if (_settings != null && _error == null) {
        _syncReminderWithSettings(_settings!).catchError((_) {});
      }
    }
  }

  /// Update language preference
  /// This updates both the database and the app locale via EasyLocalization
  Future<void> updateLanguage(String languageCode, BuildContext context) async {
    if (_settings == null) return;

    final oldLanguage = _settings!.language;

    // Update settings in memory first
    _settings = _settings!.copyWith(language: languageCode);
    notifyListeners();

    try {
      // Update database
      final result = await _repository.updateSettings(_settings!);
      result.fold(
        (failure) {
          // Revert on failure
          _settings = _settings!.copyWith(language: oldLanguage);
          _error = failure.message;
          notifyListeners();
        },
        (_) async {
          _error = null;
          // Update app locale via EasyLocalization and persist
          await LocaleService.updateAppLocale(context, languageCode);
          debugPrint('Language updated to: $languageCode');
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
    final normalizedTheme = _normalizeTheme(theme);
    if (_settings == null && _activeUserId != null) {
      _settings = Settings(id: 0, userId: _activeUserId!);
    }
    if (_settings == null) return;

    final oldTheme = _settings!.theme;
    _settings = _settings!.copyWith(theme: normalizedTheme);
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
  Future<void> updateNotificationSettings({bool? enabled, String? time}) async {
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
        (_) async {
          _error = null;
          await _syncReminderWithSettings(_settings!);
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

  Future<void> _syncReminderWithSettings(Settings settings) async {
    await _notificationService.ensureInitialized();
    final permissionGranted = await _notificationService.requestPermissions();

    if (!permissionGranted || !settings.notificationEnabled) {
      await _notificationService.cancelDailyReminder();
      return;
    }

    final parts = settings.notificationTime.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;

    if (hour == null || minute == null) {
      debugPrint('Invalid notification time: ${settings.notificationTime}');
      return;
    }

    await _notificationService.scheduleDailyReminder(
      TimeOfDay(hour: hour, minute: minute),
    );
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

  /// Get current language flag country code.
  String get currentLanguageFlag {
    return AppLocales.flagCodeOf(language).toUpperCase();
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
  IconData get currentGoalIcon {
    final goal = dailyGoalPresets.firstWhere(
      (g) => g['xp'] == dailyGoalXP,
      orElse: () => dailyGoalPresets[2],
    );
    return goal['icon'] as IconData;
  }

  /// Get ThemeMode from settings
  ThemeMode get themeMode {
    switch (theme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _normalizeTheme(String? rawTheme) {
    switch ((rawTheme ?? '').trim().toLowerCase()) {
      case 'light':
        return 'light';
      case 'dark':
        return 'dark';
      case 'system':
        return 'system';
      default:
        return 'system';
    }
  }
}
