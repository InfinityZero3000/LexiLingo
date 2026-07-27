import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/services/sound_service.dart';
import 'package:lexilingo_app/core/services/theme_preference_store.dart';
import 'package:lexilingo_app/features/user/domain/entities/settings.dart';
import 'package:lexilingo_app/features/user/domain/repositories/settings_repository.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsRepository _repository;
  final NotificationService _notificationService;
  final ThemePreferenceStore _themePreferenceStore;
  final ApiClient _apiClient;

  Settings? _settings;
  String? _activeUserId;
  String? _confirmedLanguage;
  late String _theme;
  Future<void> _localThemePersistenceQueue = Future.value();
  Future<void> _settingsPersistenceQueue = Future.value();
  bool _isLoading = false;
  String? _error;

  SettingsProvider({
    required SettingsRepository repository,
    required NotificationService notificationService,
    required ThemePreferenceStore themePreferenceStore,
    required ApiClient apiClient,
  }) : _repository = repository,
       _notificationService = notificationService,
       _themePreferenceStore = themePreferenceStore,
       _apiClient = apiClient {
    _theme = _themePreferenceStore.readTheme();
  }

  Future<Map<String, dynamic>> getReferralCode() {
    return _apiClient.get('/api/v1/referral/my-code');
  }

  Settings? get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Default values
  String get language => _settings?.language ?? 'en';
  int get dailyGoalXP => _settings?.dailyGoalXP ?? 50;
  String get theme => _theme;
  bool get notificationEnabled => _settings?.notificationEnabled ?? true;
  String get notificationTime => _settings?.notificationTime ?? '09:00';
  bool get soundEnabled => _settings?.soundEnabled ?? true;
  bool get pushReminderEnabled => _settings?.pushReminderEnabled ?? true;
  bool get emailReminderEnabled => _settings?.emailReminderEnabled ?? false;
  int get emailCadenceDays => _settings?.emailCadenceDays ?? 7;
  int get reminderMinDueCount => _settings?.reminderMinDueCount ?? 1;
  String get reminderTimezone =>
      _settings?.reminderTimezone ?? 'Asia/Ho_Chi_Minh';

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
  Future<void> loadSettings(String userId, [BuildContext? context]) async {
    // Skip reload if already loaded for this user — avoids spinner flash on re-entry
    if (_activeUserId == userId && _settings != null && !_isLoading) return;
    if (_activeUserId == userId && _isLoading) return;

    _activeUserId = userId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Read the locally-saved locale before touching settings so we can honour
    // a language the user picked (e.g. on the welcome screen) even when the
    // stored settings still carry the entity default ('en').
    final savedLocale = await LocaleService.getSavedLocale();

    var shouldPersistMigratedTheme = false;
    try {
      final result = await _repository.getSettings(userId);
      result.fold(
        (failure) {
          _error = failure.message;
          // Create default settings seeded with the locally-chosen locale.
          _settings = Settings(
            id: 0,
            userId: userId,
            language: savedLocale,
            theme: _theme,
          );
          _confirmedLanguage = savedLocale;
        },
        (settings) {
          // If the stored language is still the entity default ('en') but the
          // user has explicitly selected a different locale locally, honour
          // their local choice instead of overriding it.
          final effectiveLang =
              (settings.language == 'en' && savedLocale != 'en')
              ? savedLocale
              : settings.language;
          if (!_themePreferenceStore.hasPreference) {
            _theme = ThemePreferenceStore.normalizeTheme(settings.theme);
            shouldPersistMigratedTheme = true;
          }
          _settings = settings.copyWith(theme: _theme, language: effectiveLang);
          _confirmedLanguage = LocaleService.normalizeLanguageCode(
            effectiveLang,
          );
        },
      );
      if (shouldPersistMigratedTheme) {
        try {
          await _themePreferenceStore.writeTheme(_theme);
        } catch (e) {
          _error = e.toString();
        }
      }
    } catch (e) {
      _error = e.toString();
      // Keep settings usable even if cached payload is malformed.
      _settings = Settings(
        id: 0,
        userId: userId,
        language: savedLocale,
        theme: _theme,
      );
      _confirmedLanguage = savedLocale;
    } finally {
      _isLoading = false;
      SoundService.instance.setEnabled(_settings?.soundEnabled ?? true);
      notifyListeners();
      final effectiveLanguage = _settings?.language;
      if (effectiveLanguage != null && context?.mounted == true) {
        try {
          await LocaleService.updateAppLocale(context!, effectiveLanguage);
        } catch (e) {
          _error = e.toString();
          notifyListeners();
        }
      }
      // Sync reminder asynchronously — must not block isLoading flag.
      if (_settings != null && _error == null) {
        _syncReminderWithSettings(_settings!).catchError((_) {});
      }
    }
  }

  /// Update language preference
  /// This updates both the database and the app locale via EasyLocalization
  Future<void> updateLanguage(String languageCode, BuildContext context) async {
    if (_settings == null || !context.mounted) return;

    final oldLanguage = LocaleService.normalizeLanguageCode(
      _settings!.language,
    );
    final newLanguage = LocaleService.normalizeLanguageCode(languageCode);

    _settings = _settings!.copyWith(language: newLanguage);
    _error = null;
    notifyListeners();

    try {
      final committed = await LocaleService.updateAppLocale(
        context,
        newLanguage,
      );
      if (!committed || _settings?.language != newLanguage) return;

      final persistence = _settingsPersistenceQueue.then((_) async {
        if (_settings?.language != newLanguage) return null;
        final result = await _persistUserSettings(
          _settings!.copyWith(language: newLanguage),
        );
        if (result == null) _confirmedLanguage = newLanguage;
        return result;
      });
      _settingsPersistenceQueue = persistence.then<void>((_) {});
      final persistenceError = await persistence;
      if (persistenceError == null) {
        _error = null;
        debugPrint('Language updated to: $newLanguage');
        return;
      }
      final rollbackLanguage = _rollbackLanguageState(
        newLanguage,
        oldLanguage,
        persistenceError,
      );
      if (rollbackLanguage != null && context.mounted) {
        await LocaleService.updateAppLocale(context, rollbackLanguage);
      }
    } catch (e) {
      final rollbackLanguage = _rollbackLanguageState(
        newLanguage,
        oldLanguage,
        e,
      );
      if (rollbackLanguage != null && context.mounted) {
        await LocaleService.updateAppLocale(context, rollbackLanguage);
      }
    }
  }

  String? _rollbackLanguageState(
    String failedLanguage,
    String fallbackLanguage,
    Object error,
  ) {
    if (_settings?.language != failedLanguage) return null;
    final rollbackLanguage = _confirmedLanguage ?? fallbackLanguage;
    _settings = _settings!.copyWith(language: rollbackLanguage);
    _error = error.toString();
    notifyListeners();
    return rollbackLanguage;
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
    final normalizedTheme = ThemePreferenceStore.normalizeTheme(theme);
    _theme = normalizedTheme;
    if (_settings == null && _activeUserId != null) {
      _settings = Settings(id: 0, userId: _activeUserId!);
    }
    if (_settings != null) {
      _settings = _settings!.copyWith(theme: normalizedTheme);
    }
    _error = null;
    notifyListeners();

    final intendedTheme = normalizedTheme;
    final localPersistence = _localThemePersistenceQueue.then(
      (_) => _persistLocalTheme(normalizedTheme),
    );
    _localThemePersistenceQueue = localPersistence.then<void>((_) {});

    final settingsPersistence = _settingsPersistenceQueue.then(
      (_) => _persistUserSettings(
        _settings?.copyWith(
          theme: intendedTheme,
          language: _confirmedLanguage ?? _settings!.language,
        ),
      ),
    );
    _settingsPersistenceQueue = settingsPersistence.then<void>((_) {});

    final persistenceErrors = await Future.wait([
      localPersistence,
      settingsPersistence,
    ]);
    String? persistenceError;
    for (final error in persistenceErrors) {
      if (error != null) {
        persistenceError = error;
        break;
      }
    }

    if (persistenceError != null && _theme == normalizedTheme) {
      _error = persistenceError;
      notifyListeners();
    }
  }

  Future<String?> _persistLocalTheme(String normalizedTheme) async {
    try {
      await _themePreferenceStore.writeTheme(normalizedTheme);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> _persistUserSettings(Settings? settingsToPersist) async {
    if (settingsToPersist == null) return null;

    try {
      final result = await _repository.updateSettings(settingsToPersist);
      return result.fold((failure) => failure.message, (_) => null);
    } catch (e) {
      return e.toString();
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

  /// Update backend-managed review reminder channels.
  Future<void> updateReminderChannels({
    bool? pushEnabled,
    bool? emailEnabled,
    int? emailCadenceDays,
    int? minDueCount,
  }) async {
    if (_settings == null) return;

    final oldSettings = _settings!;
    _settings = _settings!.copyWith(
      pushReminderEnabled: pushEnabled ?? oldSettings.pushReminderEnabled,
      emailReminderEnabled: emailEnabled ?? oldSettings.emailReminderEnabled,
      emailCadenceDays: emailCadenceDays ?? oldSettings.emailCadenceDays,
      reminderMinDueCount: minDueCount ?? oldSettings.reminderMinDueCount,
    );
    notifyListeners();

    try {
      final result = await _repository.updateSettings(_settings!);
      result.fold(
        (failure) {
          _settings = oldSettings;
          _error = failure.message;
          notifyListeners();
        },
        (_) async {
          _error = null;
          await _syncReminderWithSettings(_settings!);
        },
      );
    } catch (e) {
      _settings = oldSettings;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _syncReminderWithSettings(Settings settings) async {
    await _notificationService.ensureInitialized();
    final permissionGranted = await _notificationService.requestPermissions();

    if (!permissionGranted ||
        !settings.notificationEnabled ||
        !settings.pushReminderEnabled) {
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

    SoundService.instance.setEnabled(enabled);

    final oldEnabled = _settings!.soundEnabled;
    _settings = _settings!.copyWith(soundEnabled: enabled);
    notifyListeners();

    try {
      final result = await _repository.updateSettings(_settings!);
      result.fold(
        (failure) {
          _settings = _settings!.copyWith(soundEnabled: oldEnabled);
          SoundService.instance.setEnabled(oldEnabled);
          _error = failure.message;
          notifyListeners();
        },
        (_) {
          _error = null;
        },
      );
    } catch (e) {
      _settings = _settings!.copyWith(soundEnabled: oldEnabled);
      SoundService.instance.setEnabled(oldEnabled);
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
}
