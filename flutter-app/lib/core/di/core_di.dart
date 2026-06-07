import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/interceptors/logging_interceptor.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/core/services/health_check_service.dart';
import 'package:lexilingo_app/core/services/firestore_service.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/services/streak_service.dart';
import 'package:lexilingo_app/core/services/dictionary_service.dart';
import 'package:lexilingo_app/core/services/quick_save_vocabulary_service.dart';
import 'package:lexilingo_app/core/services/theme_preference_store.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
// import 'package:lexilingo_app/core/services/course_import_service.dart'; // Disabled - old schema
import 'service_locator.dart';

Future<bool> _refreshBackendToken(TokenStorage tokenStorage) async {
  try {
    final tokens = await tokenStorage.getTokens();
    if (tokens == null || tokens.refreshToken.isEmpty) {
      return false;
    }

    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/auth/refresh'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'refresh_token': tokens.refreshToken}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = body['access_token'] as String?;
    final refreshToken = body['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      return false;
    }

    await tokenStorage.updateTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Registers cross-cutting core dependencies.
Future<void> registerCore({required bool skipDatabase}) async {
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton<SharedPreferences>(() => sharedPreferences);
  sl.registerLazySingleton<ThemePreferenceStore>(
    () => ThemePreferenceStore(sl<SharedPreferences>()),
  );

  sl.registerLazySingleton<FirestoreService>(() => FirestoreService.instance);
  sl.registerLazySingleton<NetworkInfo>(() => NetworkInfoImpl());

  // Register TokenStorage for backend JWT authentication
  sl.registerLazySingleton<TokenStorage>(() => TokenStorage());

  // Register BackendAuthHeaderProvider instead of FirebaseAuthHeaderProvider
  sl.registerLazySingleton<BackendAuthHeaderProvider>(
    () => BackendAuthHeaderProvider(tokenStorage: sl<TokenStorage>()),
  );

  // Main API Client for Backend Service (Auth, Courses, Gamification)
  sl.registerLazySingleton<ApiClient>(
    () => ApiClient(
      networkInfo: sl<NetworkInfo>(),
      interceptors: [LoggingInterceptor()],
      authHeaderProvider: sl<BackendAuthHeaderProvider>().call,
      onUnauthorized: () => _refreshBackendToken(sl<TokenStorage>()),
    ),
  );

  // AI API Client for AI Service (Chat, STT, TTS, AI Analysis)
  sl.registerLazySingleton<AiApiClient>(
    () => AiApiClient(
      networkInfo: sl<NetworkInfo>(),
      interceptors: [LoggingInterceptor()],
      authHeaderProvider: sl<BackendAuthHeaderProvider>().call,
      onUnauthorized: () => _refreshBackendToken(sl<TokenStorage>()),
    ),
  );

  sl.registerLazySingleton<HealthCheckService>(
    () => HealthCheckService(apiClient: sl<ApiClient>()),
  );
  sl.registerLazySingleton<QuickSaveVocabularyService>(
    () => QuickSaveVocabularyService(apiClient: sl<ApiClient>()),
  );
  sl.registerLazySingleton<NotificationService>(() => NotificationService());
  sl.registerLazySingleton<StreakService>(() => StreakService());
  sl.registerLazySingleton<DictionaryService>(() => DictionaryService());

  if (!skipDatabase) {
    sl.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper.instance);
    // Commented out - CourseImportService uses old schema
    // sl.registerLazySingleton<CourseImportService>(() => CourseImportService(sl()));
  }
}

/// AI API Client - connects to AI Service for chat, STT, TTS
class AiApiClient extends ApiClient {
  AiApiClient({
    super.networkInfo,
    super.interceptors,
    super.authHeaderProvider,
    super.onUnauthorized,
  }) : super(baseUrl: ApiConfig.aiServiceUrl);
}
