import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/constants.dart';

/// Centralized API configuration sourced from .env with safe defaults.
class ApiConfig {
  static String get baseUrl {
    final envUrl = dotenv.env['API_BASE_URL']?.trim();
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl.endsWith('/') ? envUrl.substring(0, envUrl.length - 1) : envUrl;
    }
    return AppConstants.apiBaseUrl;
  }

  static Duration get connectTimeout => AppConstants.connectTimeout;
  static Duration get receiveTimeout => AppConstants.receiveTimeout;
}
