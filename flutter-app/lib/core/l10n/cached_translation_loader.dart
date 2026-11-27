import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps every decoded translation table in memory.
///
/// easy_localization re-reads and re-decodes both the target locale and the
/// fallback on every `setLocale`; on web each read is a network fetch, so a
/// language switch waited on two ~100 KB downloads before any text changed.
/// Tables are loaded once and shared. Startup loads only the active and
/// fallback locales; [warmSupported] fetches the rest when a language picker
/// opens so the switch that follows resolves from memory.
class CachedTranslationLoader extends AssetLoader {
  const CachedTranslationLoader();

  static const translationsPath = 'assets/i18n';

  static final Map<String, Future<Map<String, dynamic>>> _cache = {};

  static String _assetPath(String basePath, Locale locale) =>
      '$basePath/${locale.toStringWithSeparator(separator: "-")}.json';

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) {
    final assetPath = _assetPath(path, locale);
    final cached = _cache[assetPath];
    if (cached != null) return cached;
    final future = _read(assetPath);
    _cache[assetPath] = future;
    // A failed read must not stay cached, or the locale could never load.
    future.catchError((Object _) {
      _cache.remove(assetPath);
      return const <String, dynamic>{};
    });
    return future;
  }

  static Future<Map<String, dynamic>> _read(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath, cache: false);
    return json.decode(raw) as Map<String, dynamic>;
  }

  /// Loads [locales] one at a time so warming never competes with startup.
  static Future<void> preload(String path, Iterable<Locale> locales) async {
    const loader = CachedTranslationLoader();
    for (final locale in locales) {
      try {
        await loader.load(path, locale);
      } catch (error) {
        debugPrint('Translation preload failed for $locale: $error');
      }
    }
  }

  static Future<void> warmSupported(Iterable<Locale> locales) =>
      preload(translationsPath, locales);

  /// Has [locale] in memory before it becomes the app's, when the app reads its
  /// tables through this loader (it has loaded at least the startup one).
  static Future<void> warmBeforeSwitch(Locale locale) =>
      _cache.isEmpty ? Future.value() : warmSupported([locale]);

  @visibleForTesting
  static bool isCached(String path, Locale locale) =>
      _cache.containsKey(_assetPath(path, locale));

  @visibleForTesting
  static void debugClear() => _cache.clear();
}
