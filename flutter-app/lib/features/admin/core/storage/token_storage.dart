import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessKey = 'admin_access_token';
  static const _refreshKey = 'admin_refresh_token';
  static const _userKey = 'admin_user_json';

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: accessToken),
      _storage.write(key: _refreshKey, value: refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() => _storage.read(key: _accessKey);
  static Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  static Future<void> saveUser(String json) =>
      _storage.write(key: _userKey, value: json);

  static Future<String?> getUser() => _storage.read(key: _userKey);

  static Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _userKey),
    ]);
  }

  static Future<bool> hasToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
