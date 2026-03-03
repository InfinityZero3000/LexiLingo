import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/lexi_chat/data/datasources/lexi_chat_data_source.dart';
import 'package:lexilingo_app/features/lexi_chat/data/repositories/lexi_chat_repository_impl.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';

/// Register all Lexi Chat dependencies.
void registerLexiChatModule() {
  // DataSource → uses AiApiClient (port 8001)
  sl.registerLazySingleton<LexiChatDataSource>(
    () => LexiChatDataSource(apiClient: sl<AiApiClient>()),
  );

  // Repository
  sl.registerLazySingleton<LexiChatRepository>(
    () => LexiChatRepositoryImpl(dataSource: sl<LexiChatDataSource>()),
  );

  // Provider (factory → one per widget)
  sl.registerFactory<LexiChatProvider>(
    () => LexiChatProvider(repository: sl<LexiChatRepository>()),
  );
}
