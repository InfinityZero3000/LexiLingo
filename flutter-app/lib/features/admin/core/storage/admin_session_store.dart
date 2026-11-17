import 'token_storage.dart';

/// Where the admin session's tokens live. [TokenStorage] in the app; a fake in
/// tests, since secure storage has no platform channel there.
abstract class AdminSessionStore {
  Future<String?> accessToken();
  Future<String?> refreshToken();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clear();
}

class TokenStorageSessionStore implements AdminSessionStore {
  const TokenStorageSessionStore();

  @override
  Future<String?> accessToken() => TokenStorage.getAccessToken();

  @override
  Future<String?> refreshToken() => TokenStorage.getRefreshToken();

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) => TokenStorage.saveTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
  );

  @override
  Future<void> clear() => TokenStorage.clear();
}
