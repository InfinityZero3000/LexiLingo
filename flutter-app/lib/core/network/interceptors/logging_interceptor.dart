import 'dart:developer';
import 'package:lexilingo_app/core/utils/app_logger.dart';
import 'api_interceptor.dart';
import '../models.dart';

/// Basic logging interceptor; avoid verbose logs in release by guarding with level.
class LoggingInterceptor implements ApiInterceptor {
  final String tag;
  final bool enabled;

  LoggingInterceptor({this.tag = 'ApiClient', this.enabled = true});

  @override
  void onRequest(ApiRequest request) {
    if (!enabled) return;
    logDebug(tag, '[REQ] ${request.method} ${request.uri}');
    log('[REQ] ${request.method} ${request.uri} headers=${request.headers} body=${request.body}', name: tag);
  }

  @override
  void onResponse(ApiResponse response) {
    if (!enabled) return;
    logDebug(tag, '[RES] ${response.statusCode} ${response.uri}');
    log('[RES] ${response.statusCode} ${response.uri} body=${response.bodyPreview}', name: tag);
  }

  @override
  void onError(ApiError error) {
    if (!enabled) return;
    logError(tag, '[ERR] ${error.method} ${error.uri} ${error.message}');
    log('[ERR] ${error.method} ${error.uri} ${error.message}', name: tag, error: error.cause);
  }
}
