import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/chat/domain/entities/story.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/story_repository.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/story_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StoryRepositoryStub implements StoryRepository {
  @override
  Future<Either<Failure, List<StoryListItem>>> getStories({
    String? category,
    DifficultyLevel? difficultyLevel,
    int limit = 100,
  }) async => const Right([]);

  @override
  Future<Either<Failure, List<String>>> getCategories() async =>
      const Right([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StoryProvider session counters', () {
    test('recordMistakeSaved / recordWordSaved increment independently', () {
      final provider = StoryProvider(repository: _StoryRepositoryStub());

      expect(provider.mistakesSavedThisSession, 0);
      expect(provider.wordsSavedThisSession, 0);

      provider.recordMistakeSaved();
      provider.recordMistakeSaved();
      provider.recordWordSaved();

      expect(provider.mistakesSavedThisSession, 2);
      expect(provider.wordsSavedThisSession, 1);
    });

    test('clearActiveSession resets both counters', () {
      final provider = StoryProvider(repository: _StoryRepositoryStub());
      provider.recordMistakeSaved();
      provider.recordWordSaved();

      provider.clearActiveSession();

      expect(provider.mistakesSavedThisSession, 0);
      expect(provider.wordsSavedThisSession, 0);
    });

    test('endSession resets both counters', () {
      final provider = StoryProvider(repository: _StoryRepositoryStub());
      provider.recordMistakeSaved();
      provider.recordWordSaved();

      provider.endSession();

      expect(provider.mistakesSavedThisSession, 0);
      expect(provider.wordsSavedThisSession, 0);
    });
  });
}
