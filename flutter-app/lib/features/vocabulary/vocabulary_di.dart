import 'package:get_it/get_it.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocabulary_remote_datasource.dart';
import 'package:lexilingo_app/features/vocabulary/data/repositories/vocabulary_repository_impl.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_due_vocabulary_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/submit_review_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_user_collection_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_to_collection_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/core/network/api_client.dart';

/// Vocabulary Dependency Injection Setup
/// Clean Architecture: Dependency inversion principle
/// All dependencies are injected, not created
final getIt = GetIt.instance;

void setupVocabularyDependencies() {
  // Data Sources
  getIt.registerLazySingleton<VocabularyRemoteDataSource>(
    () => VocabularyRemoteDataSourceImpl(
      apiClient: getIt<ApiClient>(),
    ),
  );

  // Repositories
  getIt.registerLazySingleton<VocabularyRepository>(
    () => VocabularyRepositoryImpl(
      remoteDataSource: getIt<VocabularyRemoteDataSource>(),
    ),
  );

  // Use Cases
  getIt.registerLazySingleton(
    () => GetDueVocabularyUseCase(getIt<VocabularyRepository>()),
  );
  
  getIt.registerLazySingleton(
    () => SubmitReviewUseCase(getIt<VocabularyRepository>()),
  );
  
  getIt.registerLazySingleton(
    () => GetUserCollectionUseCase(getIt<VocabularyRepository>()),
  );
  
  getIt.registerLazySingleton(
    () => AddToCollectionUseCase(getIt<VocabularyRepository>()),
  );

  // Providers (ChangeNotifier)
  getIt.registerFactory(
    () => FlashcardProvider(
      getDueVocabularyUseCase: getIt<GetDueVocabularyUseCase>(),
      submitReviewUseCase: getIt<SubmitReviewUseCase>(),
      vocabularyRepository: getIt<VocabularyRepository>(),
    ),
  );
}
