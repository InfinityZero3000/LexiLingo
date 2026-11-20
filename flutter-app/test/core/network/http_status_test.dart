import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/network/http_status.dart';
import 'package:lexilingo_app/core/network/response_models.dart';

ApiErrorException _envelope(String code) => ApiErrorException(
  ErrorResponseEnvelope(
    error: ErrorDetail(code: code, message: 'upstream resource not found'),
    meta: RequestMeta.fromJson(const {
      'request_id': 'r',
      'timestamp': '2026-01-01T00:00:00Z',
    }),
  ),
);

void main() {
  test('reads the status the client writes', () {
    expect(
      httpStatusOf(const ServerException('Request /x failed with status 403')),
      403,
    );
    expect(
      httpStatusOf(Exception('Request /x failed with status code: 422')),
      422,
    );
  });

  test('an id with 403 in it is not a 403, a 500 stays a 500', () {
    expect(
      httpStatusOf(
        const ServerException(
          'Request /lexi/sessions/ab403cd1-0000/delete failed with status 500',
        ),
      ),
      500,
    );
    expect(httpStatusOf(Exception('socket closed: 10.0.0.403:8000')), isNull);
  });

  test('a message that names a status is never reinterpreted by its words', () {
    expect(
      httpStatusOf(
        const ServerException(
          'Request /x failed with status 500: upstream not found, '
          'forbidden by proxy, unauthorized host',
        ),
      ),
      500,
    );
  });

  test('an envelope is read by its code, not by its message words', () {
    expect(httpStatusOf(_envelope(ErrorCodes.internalError)), isNull);
    expect(httpStatusOf(_envelope(ErrorCodes.notFound)), 404);
    expect(httpStatusOf(_envelope(ErrorCodes.authForbidden)), 403);
    expect(httpStatusOf(_envelope(ErrorCodes.authExpired)), 401);
    expect(httpStatusOf(_envelope(ErrorCodes.validationError)), 422);
    expect(httpStatusOf(_envelope(ErrorCodes.conflict)), 409);
  });

  test('bare words count only when there is no status at all', () {
    expect(httpStatusOf(Exception('Unauthorized')), 401);
    expect(httpStatusOf(Exception('Forbidden')), 403);
    expect(httpStatusOf(Exception('Session not found')), 404);
    expect(httpStatusOf(TimeoutException('slow')), isNull);
  });
}
