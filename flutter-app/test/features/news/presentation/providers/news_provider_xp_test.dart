import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/news/data/repositories/news_repository.dart';
import 'package:lexilingo_app/features/news/domain/entities/news_entities.dart';
import 'package:lexilingo_app/features/news/presentation/providers/news_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// XP for a finished news quiz.
///
/// `news_quiz_screen` used to award it too, with the bare article id as
/// `source_id` while the provider used `news_quiz_<id>` — two different keys for
/// one quiz, so the backend's duplicate-source_id check let both through and
/// every quiz paid twice. The provider is now the only awarder.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const quiz = NewsQuiz(
    questions: [
      QuizQuestion(
        id: 1,
        type: 'comprehension',
        question: 'Q1',
        options: ['A', 'B'],
        correctIndex: 0,
      ),
      QuizQuestion(
        id: 2,
        type: 'vocabulary',
        question: 'Q2',
        options: ['A', 'B'],
        correctIndex: 0,
      ),
    ],
    totalQuestions: 2,
    xpReward: 20,
  );

  Future<_FakeNewsRepository> submit(Map<int, int> answers) async {
    final repo = _FakeNewsRepository(quiz: quiz);
    final provider = NewsProvider(repository: repo);

    await provider.loadQuiz('article-1');
    answers.forEach(provider.answerQuestion);
    provider.submitQuiz();
    await Future<void>.delayed(Duration.zero);

    return repo;
  }

  test('awards exactly once per quiz', () async {
    final repo = await submit({1: 0, 2: 0});
    expect(repo.awards, hasLength(1));
  });

  test('uses one source_id so the backend can dedup a retake', () async {
    final repo = await submit({1: 0, 2: 0});
    expect(repo.awards.single.sourceId, 'news_quiz_article-1');
  });

  test('a second submit on the same quiz awards nothing more', () async {
    final repo = _FakeNewsRepository(quiz: quiz);
    final provider = NewsProvider(repository: repo);

    await provider.loadQuiz('article-1');
    provider.answerQuestion(1, 0);
    provider.answerQuestion(2, 0);
    provider.submitQuiz();
    provider.submitQuiz();
    await Future<void>.delayed(Duration.zero);

    expect(repo.awards, hasLength(1));
  });

  test('XP scales with the score rather than paying the full reward', () async {
    final perfect = await submit({1: 0, 2: 0});
    final half = await submit({1: 0, 2: 1});

    expect(perfect.awards.single.baseXp, 20);
    expect(half.awards.single.baseXp, 10);
  });

  test('a blank quiz earns nothing', () async {
    expect((await submit({})).awards, isEmpty);
  });

  test('an all-wrong quiz earns nothing', () async {
    expect((await submit({1: 1, 2: 1})).awards, isEmpty);
  });
}

class _Award {
  _Award(this.baseXp, this.sourceId);
  final int baseXp;
  final String sourceId;
}

class _FakeNewsRepository extends NewsRepository {
  _FakeNewsRepository({required this.quiz});

  final NewsQuiz quiz;
  final List<_Award> awards = [];

  @override
  Future<NewsQuiz?> getQuiz(String articleId) async => quiz;

  @override
  Future<void> awardQuizXp({
    required int baseXp,
    required String sourceId,
  }) async {
    awards.add(_Award(baseXp, sourceId));
  }
}
