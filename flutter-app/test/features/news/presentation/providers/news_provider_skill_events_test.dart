import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/skill_event_recorder.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/news/data/repositories/news_repository.dart';
import 'package:lexilingo_app/features/news/domain/entities/news_entities.dart';
import 'package:lexilingo_app/features/news/presentation/providers/news_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A news quiz used to be graded on the device and thrown away, so reading
/// stayed at zero no matter how many articles a learner worked through.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const quiz = NewsQuiz(
    questions: [
      QuizQuestion(
        id: 1,
        type: 'comprehension',
        question: 'What is the main idea?',
        options: ['A', 'B'],
        correctIndex: 1,
      ),
      QuizQuestion(
        id: 2,
        type: 'vocabulary',
        question: 'What does "surge" mean?',
        options: ['A', 'B'],
        correctIndex: 0,
      ),
      QuizQuestion(
        id: 3,
        type: 'grammar',
        question: 'Which tense is used?',
        options: ['A', 'B'],
        correctIndex: 0,
      ),
    ],
    totalQuestions: 3,
  );

  Future<List<ExerciseResultData>> submit({
    required Map<int, int> answers,
  }) async {
    final spy = _RecorderSpy();
    final provider = NewsProvider(
      repository: _FakeNewsRepository(quiz: quiz),
      skillRecorder: spy,
    );

    await provider.loadQuiz('article-1');
    answers.forEach(provider.answerQuestion);
    provider.submitQuiz();
    await Future<void>.delayed(Duration.zero);

    return spy.recorded;
  }

  test('sends one result per answered question, tagged by question type', () async {
    final results = await submit(answers: {1: 1, 2: 1, 3: 0});

    expect(results, hasLength(3));
    expect(results[0].skill, SkillType.reading); // comprehension → reading
    expect(results[0].isCorrect, isTrue);
    expect(results[1].skill, SkillType.vocabulary);
    expect(results[1].isCorrect, isFalse);
    expect(results[2].skill, SkillType.grammar);
    expect(results[2].isCorrect, isTrue);

    for (final result in results) {
      expect(result.exerciseType, 'news_quiz');
      expect(result.difficultyLevel, 'B1');
      // The quiz is graded from the article, not from a concept the schedule
      // knows about, so nothing here should land on the review queue.
      expect(result.conceptId, isNull);
    }
  });

  test('skips questions the learner never answered', () async {
    final results = await submit(answers: {2: 0});

    expect(results, hasLength(1));
    expect(results.single.skill, SkillType.vocabulary);
    expect(results.single.isCorrect, isTrue);
  });

  test('records nothing when the quiz was submitted blank', () async {
    expect(await submit(answers: {}), isEmpty);
  });
}

class _RecorderSpy implements SkillEventRecorder {
  final List<ExerciseResultData> recorded = [];

  @override
  Future<void> record(List<ExerciseResultData> results) async {
    recorded.addAll(results);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNewsRepository extends NewsRepository {
  final NewsQuiz quiz;

  _FakeNewsRepository({required this.quiz});

  @override
  Future<NewsQuiz?> getQuiz(String articleId) async => quiz;
}
