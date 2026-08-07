import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_content_model.dart';
import 'package:lexilingo_app/features/learning/domain/entities/answer_response.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_attempt.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_complete.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/complete_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_course_roadmap_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_lesson_content_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/start_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/submit_answer_usecase.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';
import 'package:provider/provider.dart';

void main() {
  test('maps matching and reorder exercise types without fallback', () {
    final exercises = ['matching', 'reorder']
        .map(
          (type) => ExerciseModel.fromJson({
            'id': type,
            'type': type,
            'question': 'Question',
            'correct_answer': 'Answer',
          }).toEntity(),
        )
        .toList();

    expect(
      exercises.map((exercise) => exercise.type),
      [ExerciseType.matching, ExerciseType.reorder],
    );
  });

  testWidgets('all canonical ui types route to their session widgets', (
    tester,
  ) async {
    final contract = jsonDecode(
      File('../contracts/content-agent/exercise-types-v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final canonicalTypes = Map<String, String>.from(
      contract['ui_type_to_type'] as Map,
    );
    const expectedWidgets = <String, Type>{
      'multiple_choice': MultipleChoiceWidget,
      'true_or_false': TrueOrFalseWidget,
      'fill_in_the_blank': FillBlankWidget,
      'arrange_the_sentence': ArrangeSentenceWidget,
      'translation_choice': TranslationChoiceWidget,
      'dialogue_completion': DialogueCompletionWidget,
      'collocation_choice': CollocationChoiceWidget,
      'dictation': DictationWidget,
      'grammar_correction': GrammarCorrectionWidget,
      'image_based_choice': ImageBasedChoiceWidget,
      'listen_and_choose': ListeningChoiceWidget,
      'match_word_to_meaning': MatchWordMeaningWidget,
      'vocabulary_flashcard': VocabularyFlashcardWidget,
      'pronunciation_practice': PronunciationPracticeWidget,
      'reading_comprehension': ReadingComprehensionWidget,
      'short_writing_answer': ShortWritingAnswerWidget,
      'speaking_repeat': SpeakingRepeatWidget,
      'categorization': CategorizationWidget,
      'cognitive_fluidity': CognitiveFluidityWidget,
    };

    expect(expectedWidgets.keys.toSet(), canonicalTypes.keys.toSet());
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _FakeLearningRepository(_lesson(canonicalTypes));
    final provider = LearningProvider(
      startLessonUseCase: StartLessonUseCase(repository: repository),
      submitAnswerUseCase: SubmitAnswerUseCase(repository: repository),
      completeLessonUseCase: CompleteLessonUseCase(repository: repository),
      getCourseRoadmapUseCase: GetCourseRoadmapUseCase(repository: repository),
      getLessonContentUseCase: GetLessonContentUseCase(repository: repository),
    );
    final showScreen = ValueNotifier(true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => TtsSettingsProvider()),
        ],
        child: ValueListenableBuilder<bool>(
          valueListenable: showScreen,
          builder: (context, show, child) => MaterialApp(
            home: show
                ? const LearningSessionScreen(
                    lessonId: 'lesson',
                    courseId: 'course',
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final entry in canonicalTypes.entries) {
      expect(
        find.byType(expectedWidgets[entry.key]!),
        findsOneWidget,
        reason: '${entry.key} did not route to its implemented widget',
      );
      if (entry.key != canonicalTypes.keys.last) {
        provider.nextExercise();
        await tester.pump();
      }
    }

    showScreen.value = false;
    await tester.pump();
    showScreen.dispose();
    provider.dispose();
  });

  testWidgets('listening widgets forward audioUrl to SpeakIconButton', (
    tester,
  ) async {
    const audioUrl = 'https://cdn.example.test/audio/question.mp3';
    final exercise = Exercise(
      id: 'audio',
      type: ExerciseType.fillInBlank,
      question: 'Listen carefully',
      options: const ['one', 'two'],
      correctAnswer: 'one',
      audioUrl: audioUrl,
    );

    for (final widget in <Widget>[
      DictationWidget(
        exercise: exercise,
        onAnswer: (_) {},
        isAnswered: false,
      ),
      ListeningChoiceWidget(
        exercise: exercise,
        onAnswer: (_) {},
        isAnswered: false,
      ),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));

      final button = tester.widget<SpeakIconButton>(
        find.byType(SpeakIconButton),
      );
      expect(button.audioUrl, audioUrl);
    }
  });
}

LessonEntity _lesson(Map<String, String> uiTypes) => LessonEntity(
  id: 'lesson',
  title: 'Contract lesson',
  outcome: 'Can complete this task',
  orderIndex: 0,
  estimatedMinutes: 5,
  xpReward: 10,
  exercises: uiTypes.entries
      .map(
        (entry) => Exercise(
          id: entry.key,
          type: _exerciseType(entry.value),
          uiType: entry.key,
          phase: 'pre_task',
          question: 'Complete this {blank} question?',
          options: const ['one', 'two', 'food', 'travel'],
          correctAnswer: 'one',
        ),
      )
      .toList(),
);

ExerciseType _exerciseType(String type) => switch (type) {
  'multiple_choice' => ExerciseType.multipleChoice,
  'true_false' => ExerciseType.trueFalse,
  'fill_blank' => ExerciseType.fillInBlank,
  'translate' => ExerciseType.translate,
  'matching' => ExerciseType.matching,
  'reorder' => ExerciseType.reorder,
  _ => throw ArgumentError.value(type, 'type'),
};

class _FakeLearningRepository implements LearningRepository {
  final LessonEntity lesson;

  _FakeLearningRepository(this.lesson);

  @override
  Future<Either<Failure, LessonAttempt>> startLesson(String lessonId) async =>
      Right(
        LessonAttempt(
          attemptId: 'attempt',
          lessonId: lessonId,
          startedAt: DateTime(2026),
          totalQuestions: lesson.exercises.length,
          livesRemaining: 3,
          hintsAvailable: 3,
        ),
      );

  @override
  Future<Either<Failure, LessonEntity>> getLessonContent(String lessonId) async =>
      Right(lesson);

  @override
  Future<Either<Failure, AnswerResponse>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String questionType,
    required dynamic userAnswer,
    required int timeSpentMs,
    bool hintUsed = false,
    double? confidenceScore,
  }) => throw UnsupportedError('submitAnswer is not used by this test');

  @override
  Future<Either<Failure, LessonComplete>> completeLesson(String attemptId) =>
      throw UnsupportedError('completeLesson is not used by this test');

  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(String courseId) =>
      throw UnsupportedError('getCourseRoadmap is not used by this test');
}
