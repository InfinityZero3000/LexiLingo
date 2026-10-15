import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/error/failure_mapper.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/response_models.dart';

ApiErrorException _apiError(String code, String message) {
  return ApiErrorException(
    ErrorResponseEnvelope(
      error: ErrorDetail(code: code, message: message),
      meta: const RequestMeta(requestId: 'req-1', timestamp: '2026-08-13'),
    ),
  );
}

void main() {
  test('API errors surface the server message, never the exception dump', () {
    final failure = mapFailure(
      _apiError(ErrorCodes.conflict, 'Lesson content is missing exercises'),
    );

    expect(failure, isA<ConflictFailure>());
    expect(failure.message, 'Lesson content is missing exercises');
    expect(failure.message, isNot(contains('ApiErrorException')));
  });

  test('error codes map to the matching failure type', () {
    expect(mapFailure(_apiError(ErrorCodes.notFound, 'x')), isA<NotFoundFailure>());
    expect(
      mapFailure(_apiError(ErrorCodes.validationError, 'x')),
      isA<ValidationFailure>(),
    );
    expect(
      mapFailure(_apiError(ErrorCodes.authExpired, 'x')),
      isA<AuthFailure>(),
    );
    expect(
      mapFailure(_apiError(ErrorCodes.rateLimited, 'x')),
      isA<RateLimitFailure>(),
    );
    expect(
      mapFailure(_apiError('SOMETHING_NEW', 'x')),
      isA<ServerFailure>(),
    );
  });

  test('transport exceptions keep their own message', () {
    expect(mapFailure(const NetworkException('offline')).message, 'offline');
    expect(mapFailure(const CacheException('no cache')), isA<CacheFailure>());
    expect(mapFailure(const ServerException('boom')), isA<ServerFailure>());
  });

  test('unknown errors use the caller fallback instead of toString', () {
    final failure = mapFailure(
      StateError('bad state'),
      fallbackMessage: 'Không tải được dữ liệu',
    );

    expect(failure, isA<UnexpectedFailure>());
    expect(failure.message, 'Không tải được dữ liệu');
  });

  test('an existing failure passes through unchanged', () {
    const original = ValidationFailure('already mapped');
    expect(identical(mapFailure(original), original), isTrue);
  });
}
