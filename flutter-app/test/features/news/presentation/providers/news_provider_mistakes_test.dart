import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/news/data/repositories/news_repository.dart';
import 'package:lexilingo_app/features/news/domain/entities/news_entities.dart';
import 'package:lexilingo_app/features/news/presentation/providers/news_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NewsProvider mistake capture', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'uses requested article id when quiz article metadata is unavailable',
      () async {
        final repository = MistakeNotebookRepository();
        final provider = NewsProvider(
          repository: _FakeNewsRepository(
            quiz: const NewsQuiz(
              questions: [
                QuizQuestion(
                  id: 1,
                  type: 'reading',
                  question: 'What is the main idea?',
                  options: ['A', 'B', 'C'],
                  correctIndex: 1,
                  explanation: 'The article supports B.',
                ),
              ],
              totalQuestions: 1,
            ),
          ),
          mistakeRepository: repository,
        );

        await provider.loadQuiz('article-123');
        provider.answerQuestion(1, 0);
        provider.submitQuiz();
        await Future<void>.delayed(Duration.zero);

        final entries = await repository.getEntries();

        expect(entries, hasLength(1));
        expect(entries.single.sourceType, 'news_quiz');
        expect(entries.single.sourceId, 'article-123');
        expect(entries.single.sourceTitle, 'News quiz');
        expect(entries.single.selectedAnswer, 'A');
        expect(entries.single.correctAnswer, 'B');
      },
    );
  });
}

class _FakeNewsRepository extends NewsRepository {
  final NewsQuiz quiz;

  _FakeNewsRepository({required this.quiz});

  @override
  Future<NewsQuiz?> getQuiz(String articleId) async => quiz;
}
