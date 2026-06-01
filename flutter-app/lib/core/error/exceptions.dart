class ServerException implements Exception {
  final String message;
  const ServerException([this.message = 'Server Exception']);
  @override
  String toString() => 'ServerException: $message';
}

class CacheException implements Exception {
  final String message;
  const CacheException([this.message = 'Cache Exception']);
  @override
  String toString() => 'CacheException: $message';
}

class AuthException implements Exception {
  final String message;
  const AuthException([this.message = 'Auth Exception']);
  @override
  String toString() => 'AuthException: $message';
}

class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'Network Exception']);
  @override
  String toString() => 'NetworkException: $message';
}

class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException([this.message = 'Unauthorized']);
  @override
  String toString() => 'UnauthorizedException: $message';
}

class NotFoundException implements Exception {
  final String message;
  const NotFoundException([this.message = 'Not Found']);
  @override
  String toString() => 'NotFoundException: $message';
}

class BadRequestException implements Exception {
  final String message;
  const BadRequestException([this.message = 'Bad Request']);
  @override
  String toString() => 'BadRequestException: $message';
}

/// Thrown when token was successfully refreshed and request should be retried
class TokenRefreshedException implements Exception {
  const TokenRefreshedException();
}
