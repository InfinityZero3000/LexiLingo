import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';

/// Register Book feature dependencies.
void registerBooksModule() {
  // Repository
  sl.registerLazySingleton<BookRepository>(
    () => BookRepository(apiClient: sl<ApiClient>()),
  );

  // Provider
  sl.registerFactory<BookProvider>(
    () => BookProvider(repository: sl<BookRepository>()),
  );
}
