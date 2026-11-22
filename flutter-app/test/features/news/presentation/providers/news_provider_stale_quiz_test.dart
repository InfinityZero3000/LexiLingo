import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/news/data/repositories/news_repository.dart';
import 'package:lexilingo_app/features/news/domain/entities/news_entities.dart';
import 'package:lexilingo_app/features/news/presentation/providers/news_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

NewsQuiz _quiz(String question) => NewsQuiz(
  questions: [
    QuizQuestion(
      id: 1,
      type: 'comprehension',
      question: question,
      options: const ['A', 'B'],
      correctIndex: 0,
    ),
  ],
  totalQuestions: 1,
  xpReward: 10,
);

class _SlowRepo extends NewsRepository {
  final Map<String, Completer<NewsQuiz?>> pending = {};

  @override
  Future<NewsQuiz?> getQuiz(String articleId, {NewsArticle? article}) =>
      (pending[articleId] = Completer<NewsQuiz?>()).future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a late reply for a closed quiz does not resurrect it', () async {
    final repo = _SlowRepo();
    final provider = NewsProvider(repository: repo);

    final load = provider.loadQuiz('a');
    provider.resetQuiz();
    repo.pending['a']!.complete(_quiz('old'));
    await load;

    expect(provider.currentQuiz, isNull);
  });

  test(
    'a late reply for the previous article cannot overwrite the new quiz',
    () async {
      final repo = _SlowRepo();
      final provider = NewsProvider(repository: repo);

      final first = provider.loadQuiz('a');
      final second = provider.loadQuiz('b');
      repo.pending['b']!.complete(_quiz('new'));
      await second;
      repo.pending['a']!.complete(_quiz('old'));
      await first;

      expect(provider.currentQuiz!.questions.single.question, 'new');
      expect(provider.isLoadingQuiz, isFalse);
    },
  );
}
