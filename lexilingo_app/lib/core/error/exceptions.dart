class ServerException implements Exception {
  final String message;
  const ServerException([this.message = 'Server Exception']);
}

class CacheException implements Exception {
  final String message;
  const CacheException([this.message = 'Cache Exception']);
}

class AuthException implements Exception {
  final String message;
  const AuthException([this.message = 'Auth Exception']);
}
