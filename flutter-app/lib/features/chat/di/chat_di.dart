import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/database/database_helper.dart' as chat_db;
import 'package:lexilingo_app/core/services/firestore_service.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_api_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_firestore_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_local_datasource.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_local_datasource_web.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:lexilingo_app/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/create_session_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/get_chat_history_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/get_sessions_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/send_message_usecase.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';

void registerChatModule({required bool skipDatabase}) {
  if (!skipDatabase) {
    sl.registerLazySingleton<chat_db.DatabaseHelper>(
      () => chat_db.DatabaseHelper(),
    );

    sl.registerLazySingleton<ChatLocalDataSource>(
      () => ChatLocalDataSourceImpl(databaseHelper: sl<chat_db.DatabaseHelper>()),
    );
  } else {
    sl.registerLazySingleton<ChatLocalDataSource>(
      () => ChatLocalDataSourceWeb(sharedPreferences: sl()),
    );
  }

  final geminiApiKey = (dotenv.isInitialized ? dotenv.env['GEMINI_API_KEY'] : null) ?? '';
  sl.registerLazySingleton<ChatRemoteDataSource>(
    () => ChatRemoteDataSource(apiKey: geminiApiKey),
  );

  // Use AiApiClient for chat - connects to AI Service on port 8001
  sl.registerLazySingleton<ChatApiDataSource>(
    () => ChatApiDataSource(apiClient: sl<AiApiClient>()),
  );

  // Only register ChatFirestoreDataSource if FirestoreService is available
  final firestoreService = sl<FirestoreService>();
  if (firestoreService.isAvailable) {
    sl.registerLazySingleton<ChatFirestoreDataSource>(
      () => ChatFirestoreDataSourceImpl(firestoreService: firestoreService),
    );
  }

  sl.registerLazySingleton<ChatRepository>(
    () => ChatRepositoryImpl(
      localDataSource: sl(),
      remoteDataSource: sl(),
      networkInfo: sl<NetworkInfo>(),
      apiDataSource: sl(),
    ),
  );

  sl.registerLazySingleton(() => CreateSessionUseCase(sl()));
  sl.registerLazySingleton(() => GetSessionsUseCase(sl()));
  sl.registerLazySingleton(() => GetChatHistoryUseCase(sl()));
  sl.registerLazySingleton(() => SendMessageUseCase(sl()));

  sl.registerFactory(
    () => ChatProvider(
      createSessionUseCase: sl(),
      getSessionsUseCase: sl(),
      getChatHistoryUseCase: sl(),
      sendMessageUseCase: sl(),
    ),
  );
}
