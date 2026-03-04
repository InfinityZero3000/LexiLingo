import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/constants.dart';

/// Centralized API configuration sourced from .env with safe defaults.
class ApiConfig {
  static String get baseUrl {
    final envUrl = dotenv.env['API_BASE_URL']?.trim();
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl.endsWith('/')
          ? envUrl.substring(0, envUrl.length - 1)
          : envUrl;
    }
    return AppConstants.apiBaseUrl;
  }

  /// AI Service URL - lấy từ AI_SERVICE_URL trong .env, fallback localhost:8001
  static String get aiServiceUrl {
    final envUrl = dotenv.env['AI_SERVICE_URL']?.trim();
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl.endsWith('/')
          ? envUrl.substring(0, envUrl.length - 1)
          : envUrl;
    }
    return AppConstants.aiServiceUrl;
  }

  static Duration get connectTimeout => AppConstants.connectTimeout;
  static Duration get receiveTimeout => AppConstants.receiveTimeout;
}
