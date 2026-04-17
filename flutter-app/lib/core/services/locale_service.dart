import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

/// Service to manage app locale persistence
/// This ensures the locale is synced between EasyLocalization and SharedPreferences
class LocaleService {
  static const String _localeKey = 'lexi_app_locale';

  /// Save locale to SharedPreferences
  static Future<void> saveLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, languageCode);
  }

  /// Load locale from SharedPreferences
  static Future<String> getSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localeKey) ?? 'vi';
  }

  /// Clear saved locale (useful for reset)
  static Future<void> clearLocale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localeKey);
  }

  /// Update app locale - this should be called when changing language
  /// It updates both EasyLocalization and persists to SharedPreferences
  /// Note: BuildContext must be available and not disposed when this is called
  static Future<void> updateAppLocale(
    BuildContext context,
    String languageCode,
  ) async {
    try {
      // Update EasyLocalization first
      await context.setLocale(Locale(languageCode));
      
      // Persist to SharedPreferences for consistency
      await saveLocale(languageCode);
      
      debugPrint('Locale updated to: $languageCode');
    } catch (e) {
      debugPrint('Failed to update locale: $e');
    }
  }

  /// Sync EasyLocalization locale with saved locale from SharedPreferences
  /// Call this on app startup to ensure consistency
  static Future<void> syncLocale(BuildContext context) async {
    try {
      final savedLocale = await getSavedLocale();
      if (!context.mounted) return;
      final currentLocale = context.locale.languageCode;
      
      if (savedLocale != currentLocale) {
        debugPrint('Syncing locale: $currentLocale -> $savedLocale');
        await context.setLocale(Locale(savedLocale));
      }
    } catch (e) {
      debugPrint('Failed to sync locale: $e');
    }
  }
}
