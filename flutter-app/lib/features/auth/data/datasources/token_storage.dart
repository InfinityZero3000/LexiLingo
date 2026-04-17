import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/background_sync_queue_service.dart';
import '../../../../core/services/encrypted_local_cache_service.dart';
import '../../../../core/services/user_scope_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../models/auth_models.dart';

const _tag = 'TokenStorage';

/// Secure storage for authentication tokens
/// Uses flutter_secure_storage for encrypted storage on mobile,
/// and SharedPreferences (LocalStorage) on Web for reliable persistence across reloads.
class TokenStorage {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenTypeKey = 'token_type';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

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
    } else {
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

  /// Save authentication tokens securely
  Future<void> saveTokens(AuthTokens tokens) async {
    logDebug(_tag, 'Saving tokens...');
    logDebug(_tag, 'Access token length: ${tokens.accessToken.length}');
    try {
      await Future.wait([
        _write(_accessTokenKey, tokens.accessToken),
        _write(_refreshTokenKey, tokens.refreshToken),
        _write(_tokenTypeKey, tokens.tokenType),
      ]);
      logInfo(_tag, 'Tokens saved successfully');
    } catch (e) {
      logError(_tag, 'Error saving tokens', e);
      rethrow;
    }
  }

  /// Get stored access token
  Future<String?> getAccessToken() async {
    return await _read(_accessTokenKey);
  }

  /// Get stored refresh token
  Future<String?> getRefreshToken() async {
    return await _read(_refreshTokenKey);
  }

  /// Get complete stored tokens
  Future<AuthTokens?> getTokens() async {
    logDebug(_tag, 'Getting tokens...');
    try {
      final accessToken = await getAccessToken();
      final refreshToken = await getRefreshToken();
      final tokenType = await _read(_tokenTypeKey);

      logDebug(
        _tag,
        'accessToken=${accessToken != null ? "found (${accessToken.length} chars)" : "null"}',
      );
      logDebug(_tag, 'refreshToken=${refreshToken != null ? "found" : "null"}');

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
    final userScope = await UserScopeService.getActiveUserId();

    await Future.wait([
      _delete(_accessTokenKey),
      _delete(_refreshTokenKey),
      _delete(_tokenTypeKey),
    ]);

    if (userScope != null && userScope.isNotEmpty) {
      // Security hardening: wipe scoped cache + pending jobs on logout.
      await EncryptedLocalCacheService.instance.clearUserScope(userScope);
      await BackgroundSyncQueueService.instance.clearUserScope(userScope);
    }

    await UserScopeService.clearActiveUserId();
  }

  /// Clear all secure storage (complete wipe)
  Future<void> clearAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await _secureStorage.deleteAll();
    }

    await EncryptedLocalCacheService.instance.clearAll();
    // Clear pending mutation queue to avoid replay across users.
    await BackgroundSyncQueueService.instance.clearAll();
  }
}
