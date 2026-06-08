import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_due_vocabulary_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/submit_review_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';

class _RecordingVocabularyRepository extends Fake
    implements VocabularyRepository {
  int? requestedCollectionLimit;

  final vocabularyItem = VocabularyItemEntity(
    id: 'vocabulary-1',
    word: 'discover',
    definition: 'to find something for the first time',
    partOfSpeech: 'verb',
    difficultyLevel: 'A2',
    createdAt: DateTime.utc(2026, 6, 8),
  );

  final userVocabulary = UserVocabularyEntity(
    id: 'user-vocabulary-1',
    userId: 'user-1',
    vocabularyId: 'vocabulary-1',
    status: VocabularyStatus.learning,
    nextReviewDate: DateTime.utc(2026, 6, 9),
    addedAt: DateTime.utc(2026, 6, 8),
  );

  @override
  Future<Either<Failure, List<VocabularyItemEntity>>> getVocabularyItems({
    String? courseId,
    String? lessonId,
    String? difficultyLevel,
    String? tag,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    return Right([vocabularyItem]);
  }

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> getUserCollection({
    VocabularyStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    requestedCollectionLimit = limit;
    return Right([userVocabulary]);
  }
}

void main() {
  test(
    'topic session uses the production-compatible collection limit',
    () async {
      final repository = _RecordingVocabularyRepository();
      final provider = FlashcardProvider(
        getDueVocabularyUseCase: GetDueVocabularyUseCase(repository),
        submitReviewUseCase: SubmitReviewUseCase(repository),
        vocabularyRepository: repository,
      );

      await provider.startTopicSession(tag: 'general');

      expect(repository.requestedCollectionLimit, 100);
      expect(provider.errorMessage, isNull);
      expect(provider.currentSession?.totalCards, 1);

      provider.dispose();
    },
  );
}
