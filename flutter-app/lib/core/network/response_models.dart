/// Response envelope models matching backend API contract
/// Based on backend-service/app/schemas/common.py

import 'package:equatable/equatable.dart';

/// Metadata included in every API response
class RequestMeta extends Equatable {
  final String requestId;
  final String timestamp;

  const RequestMeta({
    required this.requestId,
    required this.timestamp,
  });

  factory RequestMeta.fromJson(Map<String, dynamic> json) {
    return RequestMeta(
      requestId: json['request_id'] as String,
      timestamp: json['timestamp'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'request_id': requestId,
      'timestamp': timestamp,
    };
  }

  @override
  List<Object?> get props => [requestId, timestamp];
}

/// Generic success response envelope
/// Wraps all successful API responses
class ApiResponseEnvelope<T> extends Equatable {
  final T data;
  final RequestMeta meta;

  const ApiResponseEnvelope({
    required this.data,
    required this.meta,
  });

  factory ApiResponseEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromJsonT,
  ) {
    return ApiResponseEnvelope<T>(
      data: fromJsonT(json['data']),
      meta: RequestMeta.fromJson(json['meta'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson(Object? Function(T) toJsonT) {
    return {
      'data': toJsonT(data),
      'meta': meta.toJson(),
    };
  }

  @override
  List<Object?> get props => [data, meta];
}

/// Pagination metadata for list endpoints
class PaginationMeta extends Equatable {
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  const PaginationMeta({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) {
    return PaginationMeta(
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
      total: json['total'] as int,
      totalPages: json['total_pages'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'page': page,
      'page_size': pageSize,
      'total': total,
      'total_pages': totalPages,
    };
  }

  bool get hasNextPage => page < totalPages;
  bool get hasPreviousPage => page > 1;

  @override
  List<Object?> get props => [page, pageSize, total, totalPages];
}

/// Paginated response envelope
/// Used for list endpoints with pagination
class PaginatedResponseEnvelope<T> extends Equatable {
  final List<T> data;
  final PaginationMeta pagination;
  final RequestMeta meta;

  const PaginatedResponseEnvelope({
    required this.data,
    required this.pagination,
    required this.meta,
  });

  factory PaginatedResponseEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final dataList = json['data'] as List;
    return PaginatedResponseEnvelope<T>(
      data: dataList
          .map((item) => fromJsonT(item as Map<String, dynamic>))
          .toList(),
      pagination: PaginationMeta.fromJson(
        json['pagination'] as Map<String, dynamic>,
      ),
      meta: RequestMeta.fromJson(json['meta'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T) toJsonT) {
    return {
      'data': data.map((item) => toJsonT(item)).toList(),
      'pagination': pagination.toJson(),
      'meta': meta.toJson(),
    };
  }

  @override
  List<Object?> get props => [data, pagination, meta];
}

/// Error detail in error responses
class ErrorDetail extends Equatable {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  const ErrorDetail({
    required this.code,
    required this.message,
    this.details,
  });

  factory ErrorDetail.fromJson(Map<String, dynamic> json) {
    return ErrorDetail(
      code: json['code'] as String,
      message: json['message'] as String,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      if (details != null) 'details': details,
    };
  }

  @override
  List<Object?> get props => [code, message, details];
}

/// Error response envelope
/// Returned when API request fails
class ErrorResponseEnvelope extends Equatable {
  final ErrorDetail error;
  final RequestMeta meta;

  const ErrorResponseEnvelope({
    required this.error,
    required this.meta,
  });

  factory ErrorResponseEnvelope.fromJson(Map<String, dynamic> json) {
    return ErrorResponseEnvelope(
      error: ErrorDetail.fromJson(json['error'] as Map<String, dynamic>),
      meta: RequestMeta.fromJson(json['meta'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'error': error.toJson(),
      'meta': meta.toJson(),
    };
  }

  @override
  List<Object?> get props => [error, meta];
}

/// Standard error codes matching backend
/// From backend-service/app/schemas/common.py ErrorCodes
class ErrorCodes {
  // Validation Errors
  static const String validationError = 'VALIDATION_ERROR';
  static const String invalidInput = 'INVALID_INPUT';
  static const String missingField = 'MISSING_FIELD';

  // Authentication Errors
  static const String authInvalid = 'AUTH_INVALID';
  static const String authExpired = 'AUTH_EXPIRED';
  static const String authMissing = 'AUTH_MISSING';
  static const String permissionDenied = 'PERMISSION_DENIED';

  // Resource Errors
  static const String notFound = 'NOT_FOUND';
  static const String alreadyExists = 'ALREADY_EXISTS';
  static const String conflictError = 'CONFLICT_ERROR';

  // Business Logic Errors
  static const String lessonNotUnlocked = 'LESSON_NOT_UNLOCKED';
  static const String insufficientBalance = 'INSUFFICIENT_BALANCE';
  static const String itemOutOfStock = 'ITEM_OUT_OF_STOCK';
  static const String invalidLessonState = 'INVALID_LESSON_STATE';

  // System Errors
  static const String internalError = 'INTERNAL_ERROR';
  static const String serviceUnavailable = 'SERVICE_UNAVAILABLE';
  static const String rateLimited = 'RATE_LIMITED';
  static const String databaseError = 'DATABASE_ERROR';

  ErrorCodes._();
}

/// Exception thrown when API returns error response
class ApiErrorException implements Exception {
  final ErrorResponseEnvelope errorResponse;

  ApiErrorException(this.errorResponse);

  String get code => errorResponse.error.code;
  String get message => errorResponse.error.message;
  Map<String, dynamic>? get details => errorResponse.error.details;
  String get requestId => errorResponse.meta.requestId;

  bool get isAuthError =>
      code == ErrorCodes.authInvalid ||
      code == ErrorCodes.authExpired ||
      code == ErrorCodes.authMissing;

  bool get isValidationError =>
      code == ErrorCodes.validationError ||
      code == ErrorCodes.invalidInput ||
      code == ErrorCodes.missingField;

  bool get isRateLimited => code == ErrorCodes.rateLimited;

  bool get isServerError =>
      code == ErrorCodes.internalError ||
      code == ErrorCodes.serviceUnavailable ||
      code == ErrorCodes.databaseError;

  @override
  String toString() {
    return 'ApiErrorException(code: $code, message: $message, requestId: $requestId)';
  }
}
