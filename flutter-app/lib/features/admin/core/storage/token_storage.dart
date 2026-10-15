import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Admin session tokens. Mirrors the main app's TokenStorage: secure storage on
/// mobile, SharedPreferences on web — flutter_secure_storage did not survive a
/// page reload there, which logged the admin out on every refresh.
class TokenStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessKey = 'admin_access_token';
  static const _refreshKey = 'admin_refresh_token';
  static const _userKey = 'admin_user_json';

  static Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  static Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _storage.read(key: key);
  }

  static Future<void> _delete(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      await _storage.delete(key: key);
    }
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _write(_accessKey, accessToken),
      _write(_refreshKey, refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() => _read(_accessKey);
  static Future<String?> getRefreshToken() => _read(_refreshKey);

  static Future<void> saveUser(String json) => _write(_userKey, json);

  static Future<String?> getUser() => _read(_userKey);

  static Future<void> clear() async {
    await Future.wait([
      _delete(_accessKey),
      _delete(_refreshKey),
      _delete(_userKey),
    ]);
  }

  static Future<bool> hasToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
