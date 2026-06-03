class ApiEndpoints {
  static const String baseUrl = 'https://api.lexilingo.me/api/v1';

  // Auth
  static const String userLogin = '/auth/login';
  static const String adminLogin = '/auth/admin/login';
  static const String adminRequestOtp = '/auth/admin/request-otp';
  static const String adminVerifyOtp = '/auth/admin/verify-otp';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String me = '/users/me';

  // Dashboard analytics — raw JSON (no ApiResponse wrapper)
  static const String analyticsKpis = '/admin/analytics/dashboard/kpis';
  static const String analyticsEngagement =
      '/admin/analytics/dashboard/engagement';
  static const String analyticsUserGrowth =
      '/admin/analytics/dashboard/user-growth';

  // Admin CRUD
  static const String adminCourses = '/admin/courses';
  static const String adminUnits = '/admin/units';
  static const String adminLessons = '/admin/lessons';
  static const String adminVocabulary = '/admin/vocabulary';
  static const String adminGrammar = '/admin/grammar';
  static const String adminUsers = '/admin/users';
  static const String adminAchievements = '/admin/achievements';
  static const String adminShop = '/admin/shop';
  static const String adminTestExams = '/admin/test-exams';

  // Monitoring — raw JSON (no ApiResponse wrapper)
  static const String monitoringSystem = '/admin/monitoring/system';
  static const String monitoringServices = '/admin/monitoring/services';
  static const String monitoringDbStats = '/admin/monitoring/db-stats';
}
