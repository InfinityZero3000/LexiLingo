abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server Failure']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache Failure']);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No Internet Connection']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication Failed']);
}

class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Validation Failed']);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Resource Not Found']);
}

class ConflictFailure extends Failure {
  const ConflictFailure([super.message = 'Resource Already Exists']);
}

class RateLimitFailure extends Failure {
  const RateLimitFailure([super.message = 'Rate Limit Exceeded']);
}

class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'Permission Denied']);
}
