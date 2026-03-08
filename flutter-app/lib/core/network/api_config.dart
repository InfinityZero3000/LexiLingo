import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/constants.dart';

/// Centralized API configuration sourced from .env with safe defaults.
class ApiConfig {
  static String get baseUrl {
    final envUrl = _normalizedEnvUrl('API_BASE_URL');
    if (envUrl != null) {
      if (!_mustUseProductionBackend || !_isLoopbackUrl(envUrl)) {
        return envUrl;
      }
    }

    if (_shouldUseLocalFallback) {
      return AppConstants.localApiBaseUrl;
    }

    return AppConstants.apiBaseUrl;
  }

  /// AI Service URL - production stays remote, development can fallback local.
  static String get aiServiceUrl {
    final envUrl = _normalizedEnvUrl('AI_SERVICE_URL');
    if (envUrl != null) {
      if (!_mustUseProductionBackend || !_isLoopbackUrl(envUrl)) {
        return envUrl;
      }
    }

    if (_shouldUseLocalFallback) {
      return AppConstants.localAiServiceUrl;
    }

    return AppConstants.aiServiceUrl;
  }

  static Duration get connectTimeout => AppConstants.connectTimeout;
  static Duration get receiveTimeout => AppConstants.receiveTimeout;

  static String? _normalizedEnvUrl(String key) {
    final envUrl = dotenv.env[key]?.trim();
    if (envUrl == null || envUrl.isEmpty) {
      return null;
    }

    return envUrl.endsWith('/')
        ? envUrl.substring(0, envUrl.length - 1)
        : envUrl;
  }

  static bool get _shouldUseLocalFallback => !_mustUseProductionBackend;

  static bool get _mustUseProductionBackend {
    if (kReleaseMode) {
      return true;
    }

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
