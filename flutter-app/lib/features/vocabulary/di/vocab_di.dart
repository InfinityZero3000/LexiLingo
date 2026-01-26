import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';
import 'package:lexilingo_app/features/vocabulary/data/repositories/vocab_repository_impl.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';

void registerVocabModule({required bool skipDatabase}) {
  if (!skipDatabase) {
    sl.registerLazySingleton<VocabLocalDataSource>(
      () => VocabLocalDataSource(dbHelper: sl<DatabaseHelper>()),
    );
  }

  sl.registerLazySingleton<VocabRepository>(
    () => VocabRepositoryImpl(localDataSource: skipDatabase ? null : sl()),
  );

  sl.registerLazySingleton(() => GetWordsUseCase(sl()));
  sl.registerLazySingleton(() => AddWordUseCase(sl()));

  sl.registerFactory(
    () => VocabProvider(
      getWordsUseCase: sl(),
      addWordUseCase: sl(),
    ),
  );
}
