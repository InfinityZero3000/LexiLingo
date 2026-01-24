import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/response_models.dart';

void main() {
  group('Response Models Tests', () {
    group('RequestMeta', () {
      test('should parse from JSON correctly', () {
        // Arrange
        final json = {
          'request_id': '123e4567-e89b-12d3-a456-426614174000',
          'timestamp': '2026-01-24T10:00:00Z',
        };

        // Act
        final meta = RequestMeta.fromJson(json);

        // Assert
        expect(meta.requestId, '123e4567-e89b-12d3-a456-426614174000');
        expect(meta.timestamp, '2026-01-24T10:00:00Z');
      });

      test('should serialize to JSON correctly', () {
        // Arrange
        final meta = RequestMeta(
          requestId: 'test-id',
          timestamp: '2026-01-24T10:00:00Z',
        );

        // Act
        final json = meta.toJson();

        // Assert
        expect(json['request_id'], 'test-id');
        expect(json['timestamp'], '2026-01-24T10:00:00Z');
      });
    });

    group('ApiResponseEnvelope', () {
      test('should parse success response correctly', () {
        // Arrange
        final json = {
          'data': {'message': 'success', 'value': 42},
          'meta': {
            'request_id': 'test-id',
            'timestamp': '2026-01-24T10:00:00Z',
          },
        };

        // Act
        final envelope = ApiResponseEnvelope<Map<String, dynamic>>.fromJson(
          json,
          (data) => data as Map<String, dynamic>,
        );

        // Assert
        expect(envelope.data['message'], 'success');
        expect(envelope.data['value'], 42);
        expect(envelope.meta.requestId, 'test-id');
      });
    });

    group('PaginatedResponseEnvelope', () {
      test('should parse paginated response correctly', () {
        // Arrange
        final json = {
          'data': [
            {'id': 1, 'name': 'Item 1'},
            {'id': 2, 'name': 'Item 2'},
          ],
          'pagination': {
            'page': 1,
            'page_size': 20,
            'total': 100,
            'total_pages': 5,
          },
          'meta': {
            'request_id': 'test-id',
            'timestamp': '2026-01-24T10:00:00Z',
          },
        };

        // Act
        final envelope = PaginatedResponseEnvelope<Map<String, dynamic>>.fromJson(
          json,
          (item) => item,
        );

        // Assert
        expect(envelope.data.length, 2);
        expect(envelope.data[0]['name'], 'Item 1');
        expect(envelope.pagination.page, 1);
        expect(envelope.pagination.total, 100);
        expect(envelope.pagination.hasNextPage, true);
      });

      test('hasNextPage should return false on last page', () {
        // Arrange
        final pagination = PaginationMeta(
          page: 5,
          pageSize: 20,
          total: 100,
          totalPages: 5,
        );

        // Assert
        expect(pagination.hasNextPage, false);
        expect(pagination.hasPreviousPage, true);
      });
    });

    group('ErrorResponseEnvelope', () {
      test('should parse error response correctly', () {
        // Arrange
        final json = {
          'error': {
            'code': 'AUTH_INVALID',
            'message': 'Invalid credentials',
            'details': {'field': 'password'},
          },
          'meta': {
            'request_id': 'test-id',
            'timestamp': '2026-01-24T10:00:00Z',
          },
        };

        // Act
        final envelope = ErrorResponseEnvelope.fromJson(json);

        // Assert
        expect(envelope.error.code, 'AUTH_INVALID');
        expect(envelope.error.message, 'Invalid credentials');
        expect(envelope.error.details?['field'], 'password');
      });
    });

    group('ApiErrorException', () {
      test('should identify auth errors correctly', () {
        // Arrange
        final errorResponse = ErrorResponseEnvelope(
          error: ErrorDetail(
            code: ErrorCodes.authExpired,
            message: 'Token expired',
          ),
          meta: RequestMeta(
            requestId: 'test-id',
            timestamp: '2026-01-24T10:00:00Z',
          ),
        );

        // Act
        final exception = ApiErrorException(errorResponse);

        // Assert
        expect(exception.isAuthError, true);
        expect(exception.isValidationError, false);
        expect(exception.isRateLimited, false);
      });

      test('should identify validation errors correctly', () {
        // Arrange
        final errorResponse = ErrorResponseEnvelope(
          error: ErrorDetail(
            code: ErrorCodes.validationError,
            message: 'Validation failed',
          ),
          meta: RequestMeta(
            requestId: 'test-id',
            timestamp: '2026-01-24T10:00:00Z',
          ),
        );

        // Act
        final exception = ApiErrorException(errorResponse);

        // Assert
        expect(exception.isValidationError, true);
        expect(exception.isAuthError, false);
      });

      test('should identify rate limit errors correctly', () {
        // Arrange
        final errorResponse = ErrorResponseEnvelope(
          error: ErrorDetail(
            code: ErrorCodes.rateLimited,
            message: 'Rate limit exceeded',
          ),
          meta: RequestMeta(
            requestId: 'test-id',
            timestamp: '2026-01-24T10:00:00Z',
          ),
        );

        // Act
        final exception = ApiErrorException(errorResponse);

        // Assert
        expect(exception.isRateLimited, true);
      });
    });
  });
}
