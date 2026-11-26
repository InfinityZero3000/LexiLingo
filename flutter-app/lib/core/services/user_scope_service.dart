import 'dart:convert';

import 'package:lexilingo_app/core/storage/fresh_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores and resolves active authenticated user scope for local cache/sync.
class UserScopeService {
  UserScopeService._();

  static const String _activeUserIdKey = 'active_user_id';

  static Future<void> setActiveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeUserIdKey, userId);
    await _claimLegacyDeviceData(prefs, userId);
  }

  /// Device-only data written before keys were per user, still under global
  /// names. Whoever signs in first on this device owns it: it moves to their
  /// scoped key (unless that already has a value) and the global key goes, so
  /// the next account finds nothing. Runs on every sign-in and session restore,
  /// before any provider reads these keys; once the globals are gone it is a no-op.
  static const _legacyDeviceKeys = {
    'recent_topic_ids',
    'recent_topic_ids_data',
    'notifications',
    'youtube_saved_videos',
    'youtube_watch_history',
    'podcast_follows',
    'podcast_listening_history',
    'book_saved_ids',
  };

  static const _legacyDevicePrefixes = [
    'book_progress_',
    'book_reading_data_',
    'book_saved_data_',
    'book_bookmarks_',
  ];

  /// Scoped entries first, then whatever only the legacy list had.
  static List<String> _union(List<String> scoped, List<String> legacy) => [
    ...scoped,
    ...legacy.where((e) => !scoped.contains(e)),
  ];

  /// Two JSON lists as one, or null when either is not a list: a legacy list
  /// is never dropped, and a value that is not a list keeps the scoped one.
  static String? _mergeJsonLists(String scoped, String legacy) {
    try {
      final a = jsonDecode(scoped);
      final b = jsonDecode(legacy);
      if (a is! List || b is! List) return null;
      final seen = a.map(jsonEncode).toSet();
      return jsonEncode([
        ...a,
        ...b.where((e) => !seen.contains(jsonEncode(e))),
      ]);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _claimLegacyDeviceData(
    SharedPreferences prefs,
    String userId,
  ) async {
    if (userId.isEmpty || userId == 'anonymous') return;
    for (final key in prefs.getKeys().toList()) {
      if (!_legacyDeviceKeys.contains(key) &&
          !_legacyDevicePrefixes.any(key.startsWith)) {
        continue;
      }
      final scoped = 'u:$userId:$key';
      final legacy = prefs.get(key);
      final current = prefs.get(scoped);
      if (current == null) {
        if (legacy is String) await prefs.setString(scoped, legacy);
        if (legacy is List) await prefs.setStringList(scoped, legacy.cast());
      } else if (legacy is List && current is List) {
        await prefs.setStringList(
          scoped,
          _union(current.cast(), legacy.cast()),
        );
      } else if (legacy is String && current is String) {
        final merged = _mergeJsonLists(current, legacy);
        if (merged != null) await prefs.setString(scoped, merged);
      }
      await prefs.remove(key);
    }
  }

  static Future<String?> getActiveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeUserIdKey);
  }

  /// With [expected], only that learner's scope is removed: another browser
  /// tab may since have signed someone else in.
  static Future<void> clearActiveUserId({String? expected}) async {
    final prefs = await freshPreferences();
    if (expected != null && prefs.getString(_activeUserIdKey) != expected) {
      return;
    }
    await prefs.remove(_activeUserIdKey);
  }

  static Future<String> getScopeOrDefault() async {
    return (await getActiveUserId()) ?? 'anonymous';
  }

  /// SharedPreferences key for data that belongs to one learner but is not on
  /// the server, so it survives a sign-out without ever reaching another
  /// account. The scope leads so a prefix scan stays inside one learner.
  static Future<String> scopedKey(String base) async =>
      'u:${await getScopeOrDefault()}:$base';
}
