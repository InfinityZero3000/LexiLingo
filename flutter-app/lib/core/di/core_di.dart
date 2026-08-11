import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/services/entitlement_service.dart';
import 'package:lexilingo_app/core/services/health_check_service.dart';
import 'package:lexilingo_app/core/services/firestore_service.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/services/session_expired_service.dart';
import 'package:lexilingo_app/core/services/streak_service.dart';
import 'package:lexilingo_app/core/services/dictionary_service.dart';
import 'package:lexilingo_app/core/services/quick_save_vocabulary_service.dart';
import 'package:lexilingo_app/core/services/theme_preference_store.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
// import 'package:lexilingo_app/core/services/course_import_service.dart'; // Disabled - old schema
import 'service_locator.dart';

// Mutex to prevent concurrent token refresh races.
// When multiple 401s fire simultaneously, only the first triggers a real
// refresh; the rest wait on the same Completer and reuse the result.
Completer<bool>? _tokenRefreshCompleter;

Future<bool> _refreshBackendToken(TokenStorage tokenStorage) async {
  if (_tokenRefreshCompleter != null) {
    return _tokenRefreshCompleter!.future;
  }

  _tokenRefreshCompleter = Completer<bool>();
  final completer = _tokenRefreshCompleter!;

  try {
    final tokens = await tokenStorage.getTokens();
    if (tokens == null || tokens.refreshToken.isEmpty) {
      await tokenStorage.clearTokens();
      SessionExpiredService.instance.notifyExpired();
      completer.complete(false);
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
      // Refresh token is expired or revoked — wipe local tokens and force re-login.
      await tokenStorage.clearTokens();
      SessionExpiredService.instance.notifyExpired();
      completer.complete(false);
      return false;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    // Support both flat response and envelope-wrapped {data: {...}} format.
    final data = body.containsKey('data')
        ? body['data'] as Map<String, dynamic>
        : body;
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      await tokenStorage.clearTokens();
      SessionExpiredService.instance.notifyExpired();
      completer.complete(false);
      return false;
    }

    await tokenStorage.updateTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    completer.complete(true);
    return true;
  } catch (_) {
    completer.complete(false);
    return false;
  } finally {
    _tokenRefreshCompleter = null;
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
      authHeaderProvider: sl<BackendAuthHeaderProvider>().call,
      onUnauthorized: () => _refreshBackendToken(sl<TokenStorage>()),
    ),
  );

  // AI API Client for AI Service (Chat, STT, TTS, AI Analysis)
  sl.registerLazySingleton<AiApiClient>(
    () => AiApiClient(
      networkInfo: sl<NetworkInfo>(),
      authHeaderProvider: sl<BackendAuthHeaderProvider>().call,
      onUnauthorized: () => _refreshBackendToken(sl<TokenStorage>()),
    ),
  );

  sl.registerLazySingleton<HealthCheckService>(
    () => HealthCheckService(apiClient: sl<ApiClient>()),
  );
  sl.registerLazySingleton<AnalyticsService>(
    () => AnalyticsService(apiClient: sl<ApiClient>()),
  );
  sl.registerLazySingleton<EntitlementService>(
    () => EntitlementService(apiClient: sl<ApiClient>()),
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
