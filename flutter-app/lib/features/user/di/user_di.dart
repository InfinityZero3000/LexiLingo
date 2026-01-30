import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/core/services/firestore_service.dart';
import 'package:lexilingo_app/core/services/progress_firestore_data_source.dart';
import 'package:lexilingo_app/core/services/progress_sync_service.dart';
import 'package:lexilingo_app/features/user/data/datasources/daily_goal_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/daily_goal_local_data_source_web.dart';
import 'package:lexilingo_app/features/user/data/datasources/settings_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/settings_local_data_source_web.dart';
import 'package:lexilingo_app/features/user/data/datasources/streak_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/streak_local_data_source_web.dart';
import 'package:lexilingo_app/features/user/data/datasources/user_firestore_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/user_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/user_local_data_source_web.dart';
import 'package:lexilingo_app/features/user/data/repositories/daily_goal_repository_impl.dart';
import 'package:lexilingo_app/features/user/data/repositories/settings_repository_impl.dart';
import 'package:lexilingo_app/features/user/data/repositories/streak_repository_impl.dart';
import 'package:lexilingo_app/features/user/data/repositories/user_repository_impl.dart';
import 'package:lexilingo_app/features/user/domain/repositories/daily_goal_repository.dart';
import 'package:lexilingo_app/features/user/domain/repositories/settings_repository.dart';
import 'package:lexilingo_app/features/user/domain/repositories/streak_repository.dart';
import 'package:lexilingo_app/features/user/domain/repositories/user_repository.dart';
import 'package:lexilingo_app/features/user/domain/usecases/create_user_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_current_streak_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_goal_history_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_settings_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_today_goal_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/set_daily_goal_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_user_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_daily_progress_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_settings_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_user_stats_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_user_usecase.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';

void registerUserModule({required bool skipDatabase}) {
  if (!skipDatabase) {
    sl.registerLazySingleton<UserLocalDataSource>(
      () => UserLocalDataSourceImpl(databaseHelper: sl<DatabaseHelper>()),
    );
    sl.registerLazySingleton<SettingsLocalDataSource>(
      () => SettingsLocalDataSourceImpl(databaseHelper: sl<DatabaseHelper>()),
    );
    sl.registerLazySingleton<DailyGoalLocalDataSource>(
      () => DailyGoalLocalDataSourceImpl(databaseHelper: sl<DatabaseHelper>()),
    );
    sl.registerLazySingleton<StreakLocalDataSource>(
      () => StreakLocalDataSourceImpl(databaseHelper: sl<DatabaseHelper>()),
    );
  } else {
    sl.registerLazySingleton<UserLocalDataSource>(
      () => UserLocalDataSourceWeb(sharedPreferences: sl()),
    );
    sl.registerLazySingleton<SettingsLocalDataSource>(
      () => SettingsLocalDataSourceWeb(sharedPreferences: sl()),
    );
    sl.registerLazySingleton<DailyGoalLocalDataSource>(
      () => DailyGoalLocalDataSourceWeb(sharedPreferences: sl()),
    );
    sl.registerLazySingleton<StreakLocalDataSource>(
      () => StreakLocalDataSourceWeb(sharedPreferences: sl()),
    );
  }

  // Only register Firestore data sources if FirestoreService is available
  final firestoreService = sl<FirestoreService>();
  if (firestoreService.isAvailable) {
    sl.registerLazySingleton<UserFirestoreDataSource>(
      () => UserFirestoreDataSourceImpl(firestoreService: firestoreService),
    );
    sl.registerLazySingleton<ProgressFirestoreDataSource>(
      () => ProgressFirestoreDataSourceImpl(firestoreService: firestoreService),
    );
  }

  sl.registerLazySingleton<UserRepository>(
    () => UserRepositoryImpl(
      localDataSource: sl(),
      firestoreDataSource: sl.isRegistered<UserFirestoreDataSource>() ? sl() : null,
    ),
  );
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton<DailyGoalRepository>(
    () => DailyGoalRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton<StreakRepository>(
    () => StreakRepositoryImpl(localDataSource: sl()),
  );

  sl.registerLazySingleton(() => GetUserUseCase(repository: sl()));
  sl.registerLazySingleton(() => CreateUserUseCase(repository: sl()));
  sl.registerLazySingleton(() => UpdateUserUseCase(repository: sl()));
  sl.registerLazySingleton(() => UpdateUserStatsUseCase(repository: sl()));
  sl.registerLazySingleton(() => GetSettingsUseCase(repository: sl()));
  sl.registerLazySingleton(() => UpdateSettingsUseCase(repository: sl()));
  sl.registerLazySingleton(() => GetTodayGoalUseCase(repository: sl()));
  sl.registerLazySingleton(() => SetDailyGoalUseCase(repository: sl()));
  sl.registerLazySingleton(() => UpdateDailyProgressUseCase(
        dailyGoalRepository: sl(),
        userRepository: sl(),
        streakRepository: sl(),
      ));
  sl.registerLazySingleton(() => GetCurrentStreakUseCase(repository: sl()));
  sl.registerLazySingleton(() => GetGoalHistoryUseCase(repository: sl()));

  sl.registerFactory<UserProvider>(
    () => UserProvider(
      getUserUseCase: sl(),
      updateUserUseCase: sl(),
      getSettingsUseCase: sl(),
      updateSettingsUseCase: sl(),
      getTodayGoalUseCase: sl(),
      setDailyGoalUseCase: sl(),
      updateDailyProgressUseCase: sl(),
      getCurrentStreakUseCase: sl(),
    ),
  );

  // Only register ProgressSyncService if Firestore data sources are available
  if (sl.isRegistered<UserFirestoreDataSource>() && sl.isRegistered<ProgressFirestoreDataSource>()) {
    sl.registerLazySingleton<ProgressSyncService>(
      () => ProgressSyncService(
        userLocalDataSource: sl(),
        userFirestoreDataSource: sl(),
        progressFirestoreDataSource: sl(),
        firestoreService: sl(),
      ),
    );
  }
}
