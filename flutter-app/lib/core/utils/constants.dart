class AppConstants {
  static const String appName = 'LexiLingo';
  static const String databaseName = 'lexilingo.db';
  static const int databaseVersion = 1;

  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String themeModeKey = 'theme_mode';
  static const String localeKey = 'locale';
  static const String firstTimeUserKey = 'first_time_user';

  // API Config - Backend Service (Auth, Courses, Gamification)
  static const String localApiBaseUrl = 'http://127.0.0.1:8000/api/v1';
  static const String apiBaseUrl = 'https://api.lexilingo.me/api/v1';

  // AI Service (Chat, STT, TTS, AI Analysis)
  static const String localAiServiceUrl = 'http://127.0.0.1:8001/api/v1';
  static const String aiServiceUrl = 'https://api.lexilingo.me/api/v1';

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Extended timeout for AI operations (chat, STT, TTS)
  static const Duration aiOperationTimeout = Duration(seconds: 120);
}
