import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/auth/data/datasources/auth_backend_datasource.dart';
import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
import 'package:lexilingo_app/features/auth/data/datasources/device_manager.dart';
import 'package:lexilingo_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';

void registerAuthModule() {
  // Register auth dependencies (TokenStorage is already registered in core_di.dart)
  if (!sl.isRegistered<DeviceManager>()) {
    sl.registerLazySingleton<DeviceManager>(() => DeviceManager());
  }
  
  sl.registerLazySingleton<AuthBackendDataSource>(
    () => AuthBackendDataSource(
      apiClient: sl<ApiClient>(),
      tokenStorage: sl<TokenStorage>(),
      deviceManager: sl<DeviceManager>(),
    ),
  );

  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(backendDataSource: sl<AuthBackendDataSource>()),
  );

  sl.registerLazySingleton(() => SignInWithGoogleUseCase(sl()));
  sl.registerLazySingleton(() => SignInWithEmailPasswordUseCase(sl()));
  sl.registerLazySingleton(() => SignOutUseCase(sl()));
  sl.registerLazySingleton(() => GetCurrentUserUseCase(sl()));

  sl.registerFactory(
    () => AuthProvider(
      signInWithGoogleUseCase: sl(),
      signInWithEmailPasswordUseCase: sl(),
      signOutUseCase: sl(),
      getCurrentUserUseCase: sl(),
    ),
  );
}
