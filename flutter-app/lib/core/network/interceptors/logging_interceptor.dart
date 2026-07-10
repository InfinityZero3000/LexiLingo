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
    final headers = _redactHeaders(request.headers);
    final body = _isSensitivePath(request.uri) ? '<redacted>' : request.body;
    log(
      '[REQ] ${request.method} ${request.uri} headers=$headers body=$body',
      name: tag,
    );
  }

  @override
  void onResponse(ApiResponse response) {
    if (!enabled) return;
    logDebug(tag, '[RES] ${response.statusCode} ${response.uri}');
    final body = _isSensitivePath(response.uri)
        ? '<redacted>'
        : response.bodyPreview;
    log('[RES] ${response.statusCode} ${response.uri} body=$body', name: tag);
  }

  @override
  void onError(ApiError error) {
    if (!enabled) return;
    logError(tag, '[ERR] ${error.method} ${error.uri} ${error.message}');
    log(
      '[ERR] ${error.method} ${error.uri} ${error.message}',
      name: tag,
      error: error.cause,
    );
  }

  bool _isSensitivePath(Uri uri) {
    return uri.pathSegments.contains('mistakes');
  }

  Map<String, String> _redactHeaders(Map<String, String> headers) {
    return headers.map((key, value) {
      if (key.toLowerCase() == 'authorization') {
        return MapEntry(key, '<redacted>');
      }
      return MapEntry(key, value);
    });
  }
}
