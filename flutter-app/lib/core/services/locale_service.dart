import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

/// Service to manage app locale persistence
/// This ensures the locale is synced between EasyLocalization and SharedPreferences
class LocaleService {
  static const String _localeKey = 'lexi_app_locale';
  static const Set<String> _supportedLanguageCodes = {
    'vi',
    'en',
    'ja',
    'ko',
    'zh',
    'fr',
    'es',
  };
  static int _latestRequestId = 0;
  static _LocaleRequest? _activeRequest;
  static _LocaleRequest? _pendingRequest;
  static Future<void> Function(String)? _debugApply;
  static Future<void> Function(String)? _debugPersist;

  static String normalizeLanguageCode(String? languageCode) {
    final normalized = (languageCode ?? '').trim().toLowerCase();
    if (_supportedLanguageCodes.contains(normalized)) {
      return normalized;
    }
    return 'en';
  }

  /// Save locale to SharedPreferences
  static Future<void> saveLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, normalizeLanguageCode(languageCode));
  }

  /// Load locale from SharedPreferences
  static Future<String> getSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizeLanguageCode(prefs.getString(_localeKey));
  }

  /// Clear saved locale (useful for reset)
  static Future<void> clearLocale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localeKey);
  }

  /// Update app locale - this should be called when changing language
  /// It updates both EasyLocalization and persists to SharedPreferences
  /// Note: BuildContext must be available and not disposed when this is called
  static Future<bool> updateAppLocale(
    BuildContext context,
    String languageCode,
  ) => _requestLocale(languageCode, (code) {
    if (!context.mounted) {
      throw StateError('Cannot update locale with an unmounted context');
    }
    return context.setLocale(Locale(code));
  });

  static Future<bool> _requestLocale(
    String languageCode,
    Future<void> Function(String) apply,
  ) {
    final request = _LocaleRequest(
      ++_latestRequestId,
      normalizeLanguageCode(languageCode),
      apply,
    );
    _pendingRequest?.complete(false);
    _pendingRequest = request;
    if (_activeRequest == null) unawaited(_drain());
    return request.future;
  }

  static Future<void> _drain() async {
    final request = _pendingRequest;
    if (request == null || _activeRequest != null) return;
    _pendingRequest = null;
    _activeRequest = request;

    try {
      await request.apply(request.code);
      if (request.id != _latestRequestId) {
        request.complete(false);
      } else {
        await (_debugPersist ?? saveLocale)(request.code);
        final committed = request.id == _latestRequestId;
        request.complete(committed);
        if (committed) debugPrint('Locale updated to: ${request.code}');
      }
    } catch (error, stackTrace) {
      request.completeError(error, stackTrace);
    } finally {
      _activeRequest = null;
      if (_pendingRequest != null) unawaited(_drain());
    }
  }

  @visibleForTesting
  static void debugConfigure({
    required Future<void> Function(String) apply,
    required Future<void> Function(String) persist,
  }) {
    _debugApply = apply;
    _debugPersist = persist;
  }

  @visibleForTesting
  static Future<bool> debugRequestLocale(String languageCode) {
    final apply = _debugApply;
    if (apply == null) throw StateError('Call debugConfigure first');
    return _requestLocale(languageCode, apply);
  }

  @visibleForTesting
  static void debugReset() {
    assert(_activeRequest == null && _pendingRequest == null);
    _latestRequestId = 0;
    _debugApply = null;
    _debugPersist = null;
  }
}

class _LocaleRequest {
  _LocaleRequest(this.id, this.code, this.apply);

  final int id;
  final String code;
  final Future<void> Function(String) apply;
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> get future => _completer.future;

  void complete(bool value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) _completer.completeError(error, stackTrace);
  }
}
