import 'package:lexilingo_app/core/network/response_models.dart';

final _statusText = RegExp(
  r'status(?:\s*code)?[\s:=]+(\d{3})\b',
  caseSensitive: false,
);

/// The HTTP status an API error carries, or null when it carries none.
///
/// Read, in this order: the error envelope's code; the "status NNN" the client
/// writes; and only when the message says neither, a bare "unauthorized",
/// "forbidden" or "not found". A message that already names a status is never
/// reinterpreted by its words (a 500 about an upstream "not found" is a 500),
/// and three digits that merely occur in the text, such as an id, count for
/// nothing.
int? httpStatusOf(Object error) {
  if (error is ApiErrorException) {
    switch (error.code) {
      case ErrorCodes.authInvalid:
      case ErrorCodes.authExpired:
      case ErrorCodes.authMissing:
        return 401;
      case ErrorCodes.authForbidden:
      case ErrorCodes.permissionDenied:
        return 403;
      case ErrorCodes.notFound:
        return 404;
      case ErrorCodes.validationError:
      case ErrorCodes.invalidInput:
      case ErrorCodes.missingField:
        return 422;
      case ErrorCodes.alreadyExists:
      case ErrorCodes.conflict:
        return 409;
    }
    return null;
  }
  final text = error.toString();
  final match = _statusText.firstMatch(text);
  if (match != null) return int.parse(match.group(1)!);
  final lower = text.toLowerCase();
  if (lower.contains('unauthorized')) return 401;
  if (lower.contains('forbidden')) return 403;
  if (lower.contains('not found')) return 404;
  return null;
}
