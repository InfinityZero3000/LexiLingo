import 'package:get_it/get_it.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/services/firestore_service.dart';
import 'package:lexilingo_app/core/services/progress_sync_service.dart';
import 'package:lexilingo_app/core/services/progress_firestore_data_source.dart';
import 'package:lexilingo_app/core/services/streak_service.dart';
import 'package:lexilingo_app/core/services/course_import_service.dart';
import 'package:lexilingo_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:lexilingo_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/get_current_user_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_google_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_in_with_email_password_usecase.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/sign_out_usecase.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_local_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_firestore_data_source.dart';
import 'package:lexilingo_app/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/get_chat_history_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/save_message_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/send_message_to_ai_usecase.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/course/data/datasources/course_local_data_source.dart';
import 'package:lexilingo_app/features/course/data/repositories/course_repository_impl.dart';
import 'package:lexilingo_app/features/course/domain/repositories/course_repository.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_featured_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/enroll_course_usecase.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';
import 'package:lexilingo_app/features/vocabulary/data/repositories/vocab_repository_impl.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';

// User Feature imports
import 'package:lexilingo_app/features/user/data/datasources/user_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/user_firestore_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/settings_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/daily_goal_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/streak_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/repositories/user_repository_impl.dart';
import 'package:lexilingo_app/features/user/data/repositories/settings_repository_impl.dart';
import 'package:lexilingo_app/features/user/data/repositories/daily_goal_repository_impl.dart';
import 'package:lexilingo_app/features/user/data/repositories/streak_repository_impl.dart';
import 'package:lexilingo_app/features/user/domain/repositories/user_repository.dart';
import 'package:lexilingo_app/features/user/domain/repositories/settings_repository.dart';
import 'package:lexilingo_app/features/user/domain/repositories/daily_goal_repository.dart';
import 'package:lexilingo_app/features/user/domain/repositories/streak_repository.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_user_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/create_user_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_user_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_user_stats_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_settings_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_settings_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_today_goal_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_daily_progress_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_current_streak_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_goal_history_usecase.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';

final sl = GetIt.instance; // sl = Service Locator

Future<void> initializeDependencies({bool skipDatabase = false}) async {
  // ============ Core Services ============
  // Firestore Service
  sl.registerLazySingleton<FirestoreService>(() => FirestoreService.instance);
  
  // Database Helper (skip on web platform)
  if (!skipDatabase) {
    sl.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper.instance);
  }
  
  // Notification Service
  sl.registerLazySingleton<NotificationService>(() => NotificationService());
  
  // Streak Service
  sl.registerLazySingleton<StreakService>(() => StreakService());
  
  // Course Import Service
  sl.registerLazySingleton<CourseImportService>(() => CourseImportService());

  // ============ Vocabulary Feature ============
  // Data Sources
  if (!skipDatabase) {
    sl.registerLazySingleton<VocabLocalDataSource>(
      () => VocabLocalDataSource(dbHelper: sl()),
    );
  }

  // Repositories
  sl.registerLazySingleton<VocabRepository>(
    () => VocabRepositoryImpl(localDataSource: sl()),
  );

  // Use Cases
  sl.registerLazySingleton(() => GetWordsUseCase(sl()));
  sl.registerLazySingleton(() => AddWordUseCase(sl()));

  // Providers
  sl.registerFactory(
    () => VocabProvider(
      getWordsUseCase: sl(),
      addWordUseCase: sl(),
    ),
  );

  // ============ Auth Feature ============
  // Data Sources
  sl.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSource(),
  );

  // Repositories
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(remoteDataSource: sl()),
  );

  // Use Cases
  sl.registerLazySingleton(() => SignInWithGoogleUseCase(sl()));
  sl.registerLazySingleton(() => SignInWithEmailPasswordUseCase(sl()));
  sl.registerLazySingleton(() => SignOutUseCase(sl()));
  sl.registerLazySingleton(() => GetCurrentUserUseCase(sl()));

  // Providers
  sl.registerFactory(
    () => AuthProvider(
      signInWithGoogleUseCase: sl(),
      signInWithEmailPasswordUseCase: sl(),
      signOutUseCase: sl(),
      getCurrentUserUseCase: sl(),
    ),
  );

  // ============ Chat Feature ============
  // Data Sources
  if (!skipDatabase) {
    sl.registerLazySingleton<ChatLocalDataSource>(
      () => ChatLocalDataSource(dbHelper: sl()),
    );
  }
  sl.registerLazySingleton<ChatRemoteDataSource>(
    () => ChatRemoteDataSource(apiKey: 'YOUR_API_KEY'), // TODO: Move to env file
  );
  sl.registerLazySingleton<ChatFirestoreDataSource>(
    () => ChatFirestoreDataSourceImpl(firestoreService: sl()),
  );

  // Repositories
  sl.registerLazySingleton<ChatRepository>(
    () => ChatRepositoryImpl(
      localDataSource: skipDatabase ? null : sl(),
      aiDataSource: sl(),
      firestoreDataSource: sl(),
    ),
  );

  // Use Cases
  sl.registerLazySingleton(() => SendMessageToAIUseCase(sl()));
  sl.registerLazySingleton(() => SaveMessageUseCase(sl()));
  sl.registerLazySingleton(() => GetChatHistoryUseCase(sl()));

  // Providers
  sl.registerFactory(
    () => ChatProvider(
      sendMessageToAIUseCase: sl(),
      saveMessageUseCase: sl(),
      getChatHistoryUseCase: sl(),
    ),
  );

  // ============ Course Feature ============
  // Data Sources
  if (!skipDatabase) {
    sl.registerLazySingleton<CourseLocalDataSource>(
      () => CourseLocalDataSource(dbHelper: sl()),
    );
  }

  // Repositories
  sl.registerLazySingleton<CourseRepository>(
    () => CourseRepositoryImpl(localDataSource: skipDatabase ? null : sl()),
  );

  // Use Cases
  sl.registerLazySingleton(() => GetCoursesUseCase(sl()));
  sl.registerLazySingleton(() => GetFeaturedCoursesUseCase(sl()));
  sl.registerLazySingleton(() => GetEnrolledCoursesUseCase(sl()));
  sl.registerLazySingleton(() => EnrollCourseUseCase(sl()));

  // Providers
  sl.registerFactory(
    () => CourseProvider(getCoursesUseCase: sl()),
  );

  // ============ Home Feature ============
  sl.registerFactory(
    () => HomeProvider(
      getFeaturedCoursesUseCase: sl(),
      getEnrolledCoursesUseCase: sl(),
      enrollCourseUseCase: sl(),
      streakService: sl(),
      userProvider: null, // Will be set via context
    ),
  );

  // ============ User Feature ============
  // Data Sources - Local
  if (!skipDatabase) {
    sl.registerLazySingleton<UserLocalDataSource>(
      () => UserLocalDataSourceImpl(databaseHelper: sl()),
    );
    sl.registerLazySingleton<SettingsLocalDataSource>(
      () => SettingsLocalDataSourceImpl(databaseHelper: sl()),
    );
    sl.registerLazySingleton<DailyGoalLocalDataSource>(
      () => DailyGoalLocalDataSourceImpl(databaseHelper: sl()),
    );
    sl.registerLazySingleton<StreakLocalDataSource>(
      () => StreakLocalDataSourceImpl(databaseHelper: sl()),
    );
  }
  
  // Data Sources - Firestore
  sl.registerLazySingleton<UserFirestoreDataSource>(
    () => UserFirestoreDataSourceImpl(firestoreService: sl()),
  );
  sl.registerLazySingleton<ProgressFirestoreDataSource>(
    () => ProgressFirestoreDataSourceImpl(firestoreService: sl()),
  );

  // Repositories
  sl.registerLazySingleton<UserRepository>(
    () => UserRepositoryImpl(
      localDataSource: sl(),
      firestoreDataSource: sl(),
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

  // Use Cases
  sl.registerLazySingleton(() => GetUserUseCase(repository: sl()));
  sl.registerLazySingleton(() => CreateUserUseCase(repository: sl()));
  sl.registerLazySingleton(() => UpdateUserUseCase(repository: sl()));
  sl.registerLazySingleton(() => UpdateUserStatsUseCase(repository: sl()));
  sl.registerLazySingleton(() => GetSettingsUseCase(repository: sl()));
  sl.registerLazySingleton(() => UpdateSettingsUseCase(repository: sl()));
  sl.registerLazySingleton(() => GetTodayGoalUseCase(repository: sl()));
  sl.registerLazySingleton(() => UpdateDailyProgressUseCase(
    dailyGoalRepository: sl(),
    userRepository: sl(),
    streakRepository: sl(),
  ));
  sl.registerLazySingleton(() => GetCurrentStreakUseCase(repository: sl()));
  sl.registerLazySingleton(() => GetGoalHistoryUseCase(repository: sl()));

  // Providers
  sl.registerFactory(
    () => UserProvider(
      getUserUseCase: sl(),
      updateUserUseCase: sl(),
      getSettingsUseCase: sl(),
      updateSettingsUseCase: sl(),
      getTodayGoalUseCase: sl(),
      updateDailyProgressUseCase: sl(),
      getCurrentStreakUseCase: sl(),
    ),
  );
  
  // ============ Progress Sync Service ============
  sl.registerLazySingleton<ProgressSyncService>(
    () => ProgressSyncService(
      userLocalDataSource: sl(),
      userFirestoreDataSource: sl(),
      progressFirestoreDataSource: sl(),
      firestoreService: sl(),
    ),
  );
}

