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
import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
// import 'package:lexilingo_app/core/services/course_import_service.dart'; // Disabled - old schema
import 'service_locator.dart';

/// Registers cross-cutting core dependencies.
Future<void> registerCore({required bool skipDatabase}) async {
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton<SharedPreferences>(() => sharedPreferences);

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
    ),
  );
  
  // AI API Client for AI Service (Chat, STT, TTS, AI Analysis)
  sl.registerLazySingleton<AiApiClient>(
    () => AiApiClient(
      networkInfo: sl<NetworkInfo>(),
      interceptors: [LoggingInterceptor()],
      authHeaderProvider: sl<BackendAuthHeaderProvider>().call,
    ),
  );
  
  sl.registerLazySingleton<HealthCheckService>(
    () => HealthCheckService(apiClient: sl<ApiClient>()),
  );
  sl.registerLazySingleton<NotificationService>(() => NotificationService());
  sl.registerLazySingleton<StreakService>(() => StreakService());

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
  }) : super(baseUrl: AppConstants.aiServiceUrl);
}
