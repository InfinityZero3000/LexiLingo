import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/constants.dart';

/// Centralized API configuration sourced from .env with safe defaults.
///
/// PRIMARY URL: từ env (local khi dev, production khi prod)
/// FALLBACK URL: thử khi primary không reach được (network error)
///
/// Fallback pattern trong DioClient:
///   1. Gọi với baseUrl = ApiConfig.baseUrl
///   2. Nếu DioException.type == connectionError → retry với ApiConfig.fallbackBaseUrl
///   3. Nếu fallbackBaseUrl rỗng hoặc cũng fail → throw exception
class ApiConfig {
  // ── Environment ─────────────────────────────────────────────────────────────

  static String get environment =>
      dotenv.env['ENVIRONMENT']?.trim() ?? 'development';

  static bool get isDev => environment == 'development';
  static bool get isProd => environment == 'production';

  // ── Backend URL ─────────────────────────────────────────────────────────────

  /// URL chính — local (dev) hoặc Render.com (prod).
  static String get baseUrl {
    final envUrl = _normalizedEnvUrl('API_BASE_URL');
    if (envUrl != null) {
      if (!_mustUseProductionBackend || !_isLoopbackUrl(envUrl)) {
        return envUrl;
      }
    }
    return _shouldUseLocalFallback
        ? AppConstants.localApiBaseUrl
        : AppConstants.apiBaseUrl;
  }

  /// URL dự phòng — thử khi [baseUrl] không kết nối được.
  /// Trống trong production mode (không có fallback về local).
  static String get fallbackBaseUrl {
    if (_mustUseProductionBackend) {
      return ''; // production không fallback về local
    }
    final envUrl = _normalizedEnvUrl('API_BASE_URL_FALLBACK');
    return envUrl ?? AppConstants.apiBaseUrl;
  }

  // ── AI Service URL ───────────────────────────────────────────────────────────

  /// AIS URL chính.
  static String get aiServiceUrl {
    final envUrl = _normalizedEnvUrl('AI_SERVICE_URL');
    if (envUrl != null) {
      if (!_mustUseProductionBackend || !_isLoopbackUrl(envUrl)) {
        return envUrl;
      }
    }
    return _shouldUseLocalFallback
        ? AppConstants.localAiServiceUrl
        : AppConstants.aiServiceUrl;
  }

  /// AIS URL dự phòng.
  static String get fallbackAiServiceUrl {
    if (_mustUseProductionBackend) return '';
    final envUrl = _normalizedEnvUrl('AI_SERVICE_URL_FALLBACK');
    return envUrl ?? AppConstants.aiServiceUrl;
  }

  // ── Timeouts ─────────────────────────────────────────────────────────────────

  static Duration get connectTimeout => AppConstants.connectTimeout;
  static Duration get receiveTimeout => AppConstants.receiveTimeout;

  // ── Internals ────────────────────────────────────────────────────────────────

  static String? _normalizedEnvUrl(String key) {
    final envUrl = dotenv.env[key]?.trim();
    if (envUrl == null || envUrl.isEmpty) return null;
    return envUrl.endsWith('/')
        ? envUrl.substring(0, envUrl.length - 1)
        : envUrl;
  }

  static bool get _shouldUseLocalFallback => !_mustUseProductionBackend;

  static bool get _mustUseProductionBackend {
    if (kReleaseMode) return true;
    final host = Uri.base.host.toLowerCase();
    return host.isNotEmpty && !_isLoopbackHost(host);
  }

  static bool _isLoopbackUrl(String value) {
    try {
      final uri = Uri.parse(value);
      return _isLoopbackHost(uri.host.toLowerCase());
    } catch (_) {
      return false;
    }
  }

  static bool _isLoopbackHost(String host) {
    return host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0';
  }
}
