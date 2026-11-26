import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/account_data_cleaner.dart';
import '../../../../core/services/background_sync_queue_service.dart';
import '../../../../core/services/encrypted_local_cache_service.dart';
import '../../../../core/services/user_scope_service.dart';
import '../../../../core/storage/fresh_preferences.dart';
import '../../../../core/utils/app_logger.dart';
import '../models/auth_models.dart';

const _tag = 'TokenStorage';

/// The account an access token belongs to, or null if it cannot be read.
String? tokenSubject(String accessToken) {
  try {
    final payload = jsonDecode(
      utf8.decode(
        base64Url.decode(base64Url.normalize(accessToken.split('.')[1])),
      ),
    );
    return (payload as Map)['sub']?.toString();
  } catch (_) {
    return null;
  }
}

/// Secure storage for authentication tokens
/// Uses flutter_secure_storage for encrypted storage on mobile,
/// and SharedPreferences (LocalStorage) on Web for reliable persistence across reloads.
class TokenStorage {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenTypeKey = 'token_type';
  static const String _sessionUserKey = 'session_user';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// The account this tab is signed in as. Browser tabs share storage, so what
  /// is stored may now belong to whoever signed in last in another one.
  String? _account;

  /// Whether [accessToken] is someone else's. A tab that has no account yet
  /// takes the first one it reads.
  bool _isForeign(String? accessToken) {
    final subject = accessToken == null ? null : tokenSubject(accessToken);
    if (subject == null) return false;
    return (_account ??= subject) != subject;
  }

  /// True when the stored tokens are someone else's: this tab must then neither
  /// send them nor delete them.
  Future<bool> _heldByAnotherAccount() async =>
      _isForeign(await _read(_accessTokenKey));

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      // The Android keystore can refuse a read for a moment (right after boot,
      // or while the device is still unlocking). One retry turns that into a
      // delay instead of a signed-out learner.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return await _secureStorage.read(key: key);
    }
  }

  Future<void> _delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  /// Picks up a rotation another browser tab made; see [freshPreferences].
  Future<void> reload() async {
    await freshPreferences();
  }

  /// Save authentication tokens securely
  Future<void> saveTokens(AuthTokens tokens) async {
    logDebug(_tag, 'Saving tokens...');
    logDebug(_tag, 'Access token length: ${tokens.accessToken.length}');
    try {
      // Refresh token first: it is single-use, so if the process dies between
      // writes the learner must be left holding the newest one.
      await _write(_refreshTokenKey, tokens.refreshToken);
      await _write(_accessTokenKey, tokens.accessToken);
      await _write(_tokenTypeKey, tokens.tokenType);
      _account = tokenSubject(tokens.accessToken);
      logInfo(_tag, 'Tokens saved successfully');
    } catch (e) {
      logError(_tag, 'Error saving tokens', e);
      rethrow;
    }
  }

  /// Get stored access token
  Future<String?> getAccessToken() async {
    final token = await _read(_accessTokenKey);
    return _isForeign(token) ? null : token;
  }

  /// Get stored refresh token
  Future<String?> getRefreshToken() async {
    if (await _heldByAnotherAccount()) return null;
    return await _read(_refreshTokenKey);
  }

  /// Get complete stored tokens
  Future<AuthTokens?> getTokens() async {
    try {
      final accessToken = await getAccessToken();
      final refreshToken = await getRefreshToken();
      final tokenType = await _read(_tokenTypeKey);

      if (accessToken == null || refreshToken == null) {
        logWarn(_tag, 'Tokens not found');
        return null;
      }

      return AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        tokenType: tokenType ?? 'bearer',
      );
    } catch (e) {
      logError(_tag, 'Error getting tokens', e);
      return null;
    }
  }

  /// The learner as the server last described them (`/users/me`), so a cold
  /// start can open the app at once, and offline, instead of waiting on the
  /// network to learn who is signed in.
  Future<void> saveSessionUser(String userJson) =>
      _write(_sessionUserKey, userJson);

  Future<String?> readSessionUser() async {
    try {
      if (await _heldByAnotherAccount()) return null;
      return await _read(_sessionUserKey);
    } catch (_) {
      return null;
    }
  }

  /// Update only access token (after refresh)
  Future<void> updateAccessToken(String accessToken) async {
    await _write(_accessTokenKey, accessToken);
  }

  /// Update both tokens (token rotation)
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await saveTokens(
      AuthTokens(accessToken: accessToken, refreshToken: refreshToken),
    );
  }

  /// Check if tokens exist
  Future<bool> hasTokens() async {
    final accessToken = await getAccessToken();
    final refreshToken = await getRefreshToken();
    return accessToken != null && refreshToken != null;
  }

  /// Clear all stored tokens (logout)
  Future<void> clearTokens() async {
    // Signing this tab out must not sign the other account out. [_account]
    // stays, so this tab keeps refusing their tokens until it signs in again.
    if (await _heldByAnotherAccount()) return;
    _account = null;

    final userScope = await UserScopeService.getActiveUserId();

    await Future.wait([
      _delete(_accessTokenKey),
      _delete(_refreshTokenKey),
      _delete(_tokenTypeKey),
      _delete(_sessionUserKey),
    ]);

    if (userScope != null && userScope.isNotEmpty) {
      // Security hardening: wipe scoped cache + pending jobs on logout.
      await EncryptedLocalCacheService.instance.clearUserScope(userScope);
      await BackgroundSyncQueueService.instance.clearUserScope(userScope);
    }

    await AccountDataCleaner.clear();
    await UserScopeService.clearActiveUserId();
  }

  /// Clear all secure storage (complete wipe)
  Future<void> clearAll() async {
    _account = null;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await _secureStorage.deleteAll();
    }

    await EncryptedLocalCacheService.instance.clearAll();
    await AccountDataCleaner.clear();
    // Clear pending mutation queue to avoid replay across users.
    await BackgroundSyncQueueService.instance.clearAll();
  }
}
