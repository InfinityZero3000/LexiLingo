import 'dart:io' show SocketException;

import 'package:dio/dio.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';

enum AdminErrorKind {
  network,
  unauthorized,
  forbidden,
  notFound,
  featureOff,
  server,
  unknown,
}

/// What a failed admin call means to the person looking at the screen.
///
/// 403 and 503 are ordinary states here: 403 is a permission the role does not
/// hold, 503 is an agent whose `*_ENABLED` flag is off. Screens show them as
/// such rather than as a crash.
class AdminApiError implements Exception {
  const AdminApiError(this.kind, this.message, {this.status});

  final AdminErrorKind kind;
  final UiText message;
  final int? status;

  bool get isForbidden => kind == AdminErrorKind.forbidden;
  bool get isFeatureOff => kind == AdminErrorKind.featureOff;
  bool get isNetwork => kind == AdminErrorKind.network;

  factory AdminApiError.from(Object error) {
    if (error is AdminApiError) return error;
    if (error is DioException) return _fromDio(error);
    if (error is SocketException) {
      return const AdminApiError(
        AdminErrorKind.network,
        UiText.key('admin.errors.network'),
      );
    }
    return const AdminApiError(
      AdminErrorKind.unknown,
      UiText.key('admin.errors.generic'),
    );
  }

  static AdminApiError _fromDio(DioException e) {
    final status = e.response?.statusCode;
    switch (status) {
      case 401:
        return const AdminApiError(
          AdminErrorKind.unauthorized,
          UiText.key('admin.errors.unauthorized'),
          status: 401,
        );
      case 403:
        return const AdminApiError(
          AdminErrorKind.forbidden,
          UiText.key('admin.errors.forbidden'),
          status: 403,
        );
      case 404:
        return const AdminApiError(
          AdminErrorKind.notFound,
          UiText.key('admin.errors.notFound'),
          status: 404,
        );
      case 503:
        return const AdminApiError(
          AdminErrorKind.featureOff,
          UiText.key('admin.errors.featureOff'),
          status: 503,
        );
    }
    if (status != null && status >= 500) {
      return AdminApiError(
        AdminErrorKind.server,
        const UiText.key('admin.errors.server'),
        status: status,
      );
    }
    if (status != null) {
      final detail = _detail(e.response?.data);
      return AdminApiError(
        AdminErrorKind.unknown,
        detail != null
            ? UiText.raw(detail)
            : const UiText.key('admin.errors.generic'),
        status: status,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AdminApiError(
          AdminErrorKind.network,
          UiText.key('admin.errors.network'),
        );
      default:
        return const AdminApiError(
          AdminErrorKind.unknown,
          UiText.key('admin.errors.generic'),
        );
    }
  }

  /// FastAPI puts a readable reason in `detail`; a validation error makes it a
  /// list of objects, which is not worth showing.
  static String? _detail(Object? data) {
    if (data is Map) {
      final detail = data['detail'] ?? data['message'];
      if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    }
    return null;
  }

  @override
  String toString() => message.resolve();
}
