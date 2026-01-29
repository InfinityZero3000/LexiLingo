abstract class Failure {
  final String message;
  const Failure(this.message);
  
  @override
  String toString() => message;
}

class ServerFailure extends Failure {
  const ServerFailure([String message = 'Server Failure']) : super(message);
}

class CacheFailure extends Failure {
  const CacheFailure([String message = 'Cache Failure']) : super(message);
}

class NetworkFailure extends Failure {
  const NetworkFailure([String message = 'No Internet Connection']) : super(message);
}

class AuthFailure extends Failure {
  const AuthFailure([String message = 'Authentication Failed']) : super(message);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure([String message = 'Unauthorized']) : super(message);
}

class ValidationFailure extends Failure {
  const ValidationFailure([String message = 'Validation Failed']) : super(message);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([String message = 'Resource Not Found']) : super(message);
}

class ConflictFailure extends Failure {
  const ConflictFailure([String message = 'Resource Already Exists']) : super(message);
}

class RateLimitFailure extends Failure {
  const RateLimitFailure([String message = 'Rate Limit Exceeded']) : super(message);
}

class PermissionFailure extends Failure {
  const PermissionFailure([String message = 'Permission Denied']) : super(message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([String message = 'Unexpected Error']) : super(message);
}
