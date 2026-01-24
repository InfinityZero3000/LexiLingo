import 'dart:async';
import '../models.dart';

/// Defines hooks for request/response lifecycle.
abstract class ApiInterceptor {
  FutureOr<void> onRequest(ApiRequest request) {}
  FutureOr<void> onResponse(ApiResponse response) {}
  FutureOr<void> onError(ApiError error) {}
}
