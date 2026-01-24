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

class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'Network Exception']);
}

class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException([this.message = 'Unauthorized']);
}

class NotFoundException implements Exception {
  final String message;
  const NotFoundException([this.message = 'Not Found']);
}

class BadRequestException implements Exception {
  final String message;
  const BadRequestException([this.message = 'Bad Request']);
}
