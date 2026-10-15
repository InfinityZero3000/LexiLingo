import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/response_models.dart';

/// Single translation point from transport errors to [Failure].
///
/// Repositories used to end with `catch (e) => ServerFailure(e.toString())`,
/// which leaked `ApiErrorException(code: ..., requestId: ...)` straight into
/// user-facing error text. Route every repository catch-all through here so
/// the server's own message — and its error code — survive instead.
Failure mapFailure(Object error, {String? fallbackMessage}) {
  if (error is Failure) return error;

  if (error is ApiErrorException) {
    switch (error.code) {
      case ErrorCodes.notFound:
        return NotFoundFailure(error.message);
      case ErrorCodes.conflict:
      case ErrorCodes.alreadyExists:
        return ConflictFailure(error.message);
      case ErrorCodes.validationError:
      case ErrorCodes.invalidInput:
      case ErrorCodes.missingField:
        return ValidationFailure(error.message);
      case ErrorCodes.authInvalid:
      case ErrorCodes.authExpired:
      case ErrorCodes.authMissing:
        return AuthFailure(error.message);
      case ErrorCodes.authForbidden:
      case ErrorCodes.permissionDenied:
        return PermissionFailure(error.message);
      case ErrorCodes.rateLimited:
        return RateLimitFailure(error.message);
      default:
        return ServerFailure(error.message);
    }
  }

  if (error is NetworkException) return NetworkFailure(error.message);
  if (error is UnauthorizedException) return UnauthorizedFailure(error.message);
  if (error is NotFoundException) return NotFoundFailure(error.message);
  if (error is BadRequestException) return ValidationFailure(error.message);
  if (error is AuthException) return AuthFailure(error.message);
  if (error is CacheException) return CacheFailure(error.message);
  if (error is ServerException) return ServerFailure(error.message);

  // Anything left is a genuine programming error — keep toString() for the
  // log, but callers should pass a human-readable fallback for the UI.
  return UnexpectedFailure(fallbackMessage ?? error.toString());
}
