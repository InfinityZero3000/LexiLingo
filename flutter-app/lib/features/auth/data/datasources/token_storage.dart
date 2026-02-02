import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/utils/app_logger.dart';
import '../models/auth_models.dart';

const _tag = 'TokenStorage';

/// Secure storage for authentication tokens
/// Uses flutter_secure_storage for encrypted storage
/// Falls back to in-memory storage on web for reliability
class TokenStorage {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenTypeKey = 'token_type';

  // In-memory storage for web platform as fallback
  static final Map<String, String> _memoryStorage = {};

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    webOptions: WebOptions(
      dbName: 'lexilingo_secure_storage',
      publicKey: 'lexilingo_public_key',
    ),
  );

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      // Use in-memory storage on web for reliability
      _memoryStorage[key] = value;
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      return _memoryStorage[key];
    }
    return await _storage.read(key: key);
  }

  Future<void> _delete(String key) async {
    if (kIsWeb) {
      _memoryStorage.remove(key);
    } else {
      await _storage.delete(key: key);
    }
  }

  /// Save authentication tokens securely
  Future<void> saveTokens(AuthTokens tokens) async {
    logDebug(_tag, 'Saving tokens... (isWeb: $kIsWeb)');
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
      final tokenType = await _storage.read(key: _tokenTypeKey);

      logDebug(_tag, 'accessToken=${accessToken != null ? "found (${accessToken.length} chars)" : "null"}');
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
    await saveTokens(AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    ));
  }

  /// Check if tokens exist
  Future<bool> hasTokens() async {
    final accessToken = await getAccessToken();
    final refreshToken = await getRefreshToken();
    return accessToken != null && refreshToken != null;
  }

  /// Clear all stored tokens (logout)
  Future<void> clearTokens() async {
    if (kIsWeb) {
      _memoryStorage.clear();
    } else {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
        _storage.delete(key: _tokenTypeKey),
      ]);
    }
  }

  /// Clear all secure storage (complete wipe)
  Future<void> clearAll() async {
    if (kIsWeb) {
      _memoryStorage.clear();
    } else {
      await _storage.deleteAll();
    }
  }
}
