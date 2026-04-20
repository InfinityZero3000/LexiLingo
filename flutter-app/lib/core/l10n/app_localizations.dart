// App Localizations Helper
// Usage anywhere:
//   - 'common.loading'.tr()
//   - 'home.greeting'.tr(namedArgs: {'name': 'An'})
//   - 'plural.days'.plural(5)
//   - context.locale  → current Locale
//   - context.setLocale(Locale('en'))  → change language

export 'package:easy_localization/easy_localization.dart'
    show EasyLocalization, BuildContextEasyLocalizationExtension;

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Supported locales with metadata
class AppLocales {
  static const List<Locale> supportedLocales = [
    Locale('vi'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale('fr'),
    Locale('es'),
  ];

  static const Locale fallback = Locale('vi');

  static const Map<String, Map<String, String>> metadata = {
    'vi': {'flag': '🇻🇳', 'name': 'Tiếng Việt', 'nameEn': 'Vietnamese'},
    'en': {'flag': '🇺🇸', 'name': 'English', 'nameEn': 'English'},
    'ja': {'flag': '🇯🇵', 'name': '日本語', 'nameEn': 'Japanese'},
    'ko': {'flag': '🇰🇷', 'name': '한국어', 'nameEn': 'Korean'},
    'zh': {'flag': '🇨🇳', 'name': '中文', 'nameEn': 'Chinese'},
    'fr': {'flag': '🇫🇷', 'name': 'Français', 'nameEn': 'French'},
    'es': {'flag': '🇪🇸', 'name': 'Español', 'nameEn': 'Spanish'},
  };

  static String flagOf(String code) => metadata[code]?['flag'] ?? '🌐';
  static String nameOf(String code) => metadata[code]?['name'] ?? code;
  static String nameEnOf(String code) => metadata[code]?['nameEn'] ?? code;
}

/// Extension on BuildContext for concise locale switching
extension LocaleHelper on BuildContext {
  /// Current language code e.g. 'vi', 'en'
  String get languageCode => locale.languageCode;

  /// Switch app language — updates easy_localization + persists
  Future<void> switchLocale(String languageCode) async {
    await setLocale(Locale(languageCode));
  }

  /// Check if current locale matches code
  bool isLocale(String code) => locale.languageCode == code;
}
