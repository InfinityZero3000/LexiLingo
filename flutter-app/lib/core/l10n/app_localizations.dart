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

  static const Locale fallback = Locale('en');

  static const Map<String, Map<String, String>> metadata = {
    'vi': {
      'flagCode': 'vn',
      'name': 'Tiếng Việt',
      'nameEn': 'Vietnamese',
    },
    'en': {
      'flagCode': 'us',
      'name': 'English',
      'nameEn': 'English',
    },
    'ja': {
      'flagCode': 'jp',
      'name': '日本語',
      'nameEn': 'Japanese',
    },
    'ko': {
      'flagCode': 'kr',
      'name': '한국어',
      'nameEn': 'Korean',
    },
    'zh': {
      'flagCode': 'cn',
      'name': '中文',
      'nameEn': 'Chinese',
    },
    'fr': {
      'flagCode': 'fr',
      'name': 'Français',
      'nameEn': 'French',
    },
    'es': {
      'flagCode': 'es',
      'name': 'Español',
      'nameEn': 'Spanish',
    },
  };

  static String flagCodeOf(String code) => metadata[code]?['flagCode'] ?? 'un';
  static String flagSvgUrlOf(String code) =>
      'https://flagcdn.com/${flagCodeOf(code)}.svg';
  static String flagPngUrlOf(String code) =>
      'https://flagcdn.com/w320/${flagCodeOf(code)}.png';
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
