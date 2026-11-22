import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/error/failures.dart';

/// Text held in state that must follow the current locale.
///
/// A string translated when it is stored keeps the language it was stored in,
/// so a provider's error message outlived a language switch. Store the key and
/// translate on read; server text, which cannot be re-translated, is [UiText.raw].
class UiText {
  const UiText.key(
    String key, {
    List<String>? args,
    Map<String, String>? namedArgs,
  }) : _key = key,
       _args = args,
       _namedArgs = namedArgs,
       _raw = null;

  /// A failure's own message when it carries one; its type's translated
  /// message when it only has the English default.
  factory UiText.failure(Failure failure) {
    final (fallback, key) = switch (failure) {
      NetworkFailure() => ('No Internet Connection', 'errors.networkRetry'),
      ServerFailure() => ('Server Failure', 'errors.serverRetry'),
      CacheFailure() => ('Cache Failure', 'errors.localStorage'),
      AuthFailure() => ('Authentication Failed', 'errors.authFailed'),
      UnauthorizedFailure() => ('Unauthorized', 'errors.sessionExpired'),
      ValidationFailure() => ('Validation Failed', 'errors.validation'),
      NotFoundFailure() => ('Resource Not Found', 'errors.notFoundContent'),
      ConflictFailure() => ('Resource Already Exists', 'errors.alreadyExists'),
      RateLimitFailure() => ('Rate Limit Exceeded', 'errors.rateLimited'),
      PermissionFailure() => ('Permission Denied', 'errors.permissionDenied'),
      _ => ('Unexpected Error', 'errors.genericRetry'),
    };
    final message = failure.message.trim();
    return message.isEmpty || message == fallback
        ? UiText.key(key)
        : UiText.raw(message);
  }

  const UiText.raw(String text)
    : _raw = text,
      _key = null,
      _args = null,
      _namedArgs = null;

  final String? _key;
  final List<String>? _args;
  final Map<String, String>? _namedArgs;
  final String? _raw;

  String resolve() => _raw ?? _key!.tr(args: _args, namedArgs: _namedArgs);

  @override
  String toString() => resolve();
}
