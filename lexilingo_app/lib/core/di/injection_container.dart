import 'package:get_it/get_it.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
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
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';
import 'package:lexilingo_app/features/vocabulary/data/repositories/vocab_repository_impl.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';

final sl = GetIt.instance; // sl = Service Locator

Future<void> initializeDependencies({bool skipDatabase = false}) async {
  // ============ Core ============
  // Database Helper (skip on web platform)
  if (!skipDatabase) {
    sl.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper.instance);
  }
  
  // Notification Service
  sl.registerLazySingleton<NotificationService>(() => NotificationService());

  // ============ Vocabulary Feature ============
  // Data Sources
  if (!skipDatabase) {
    sl.registerLazySingleton<VocabLocalDataSource>(
      () => VocabLocalDataSource(dbHelper: sl()),
    );
  }

  // RepositorieskipDatabase ? null : s
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

  // Repositories
  sl.registerLazySingleton<ChatRepository>(
    () => ChatRepositoryImpl(
      localDataSource: sl(),
      remoteDataSource: sl(),
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
    () => CourseRepositoryImpl(localDataSource: sl()),
  );

  // Use Cases
  sl.registerLazySingleton(() => GetCoursesUseCase(sl()));

  // Providers
  sl.registerFactory(
    () => CourseProvider(getCoursesUseCase: sl()),
  );
}
