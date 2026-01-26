class AppConstants {
  static const String appName = 'LexiLingo';
  static const String databaseName = 'lexilingo.db';
  static const int databaseVersion = 1;
  
  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String themeModeKey = 'theme_mode';
  static const String localeKey = 'locale';
  static const String firstTimeUserKey = 'first_time_user';
  
  // API Config (Mock)
  static const String apiBaseUrl = 'https://api.lexilingo.com/v1';
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
