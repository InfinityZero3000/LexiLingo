import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_cache_service.dart';

/// What a sign-out removes from the device, beyond tokens and the per-user
/// encrypted cache: caches of data the server holds, and only the learner's
/// own entries of the shared cache (public content stays, so it still works
/// offline). Device-only data is not touched here; it is keyed per user, and
/// the old global copies are claimed by the first account to sign in
/// (`UserScopeService.setActiveUserId`).
abstract final class AccountDataCleaner {
  static const _preferencePrefixes = ['topic_session_'];

  /// Written before it was keyed by learner; nobody owns it, so it goes.
  static const _preferenceKeys = {'lexilingo.last_known_league'};

  static const _secureKeys = ['lexi_saved_sessions'];

  /// Whose data the per-user caches currently hold.
  static const _ownerKey = 'cache_owner_user_id';

  /// Each storage step is bounded: this runs inside sign-out, and a storage
  /// call that never answers must not leave the learner stuck signed in.
  @visibleForTesting
  static Duration stepTimeout = const Duration(seconds: 2);

  @visibleForTesting
  static Future<void> Function()? debugUserCacheClear;

  static Future<void> clear() async {
    await Future.wait([
      _bounded('preferences', () async {
        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys().toList()) {
          if (_preferenceKeys.contains(key) ||
              _preferencePrefixes.any(key.startsWith)) {
            await prefs.remove(key);
          }
        }
        await prefs.remove(_ownerKey);
      }),
      for (final key in _secureKeys)
        _bounded(
          'secure storage',
          () => const FlutterSecureStorage().delete(key: key),
        ),
      _bounded(
        'shared cache',
        debugUserCacheClear ?? LocalCacheService.instance.clearUserEntries,
      ),
    ]);
  }

  /// Signing in clears the previous learner's caches unless they are already
  /// this learner's. A session that ended without a sign-out (a check that
  /// timed out, say) leaves tokens and caches behind; this is what keeps the
  /// next account from reading them. A learner returning on the same device
  /// keeps their caches, so a cold start does not wipe what works offline.
  static Future<void> clearForSignIn(String? userId) async {
    String? owner;
    await _bounded('preferences', () async {
      owner = (await SharedPreferences.getInstance()).getString(_ownerKey);
    });
    if (userId != null && owner == userId) return;
    await clear();
    if (userId == null) return;
    await _bounded('preferences', () async {
      await (await SharedPreferences.getInstance()).setString(
        _ownerKey,
        userId,
      );
    });
  }

  static Future<void> _bounded(
    String what,
    Future<void> Function() step,
  ) async {
    try {
      await step().timeout(stepTimeout);
    } on TimeoutException {
      debugPrint('AccountDataCleaner: $what did not answer in time; skipped');
    } catch (e) {
      debugPrint('AccountDataCleaner: $what failed: $e');
    }
  }
}
