import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
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
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';
import 'package:provider/provider.dart';

/// Regression test: each exercise widget used to keep the previous exercise's
/// local State (text controllers, matched pairs, placed words) when moving to
/// the next question of the same ui_type, because the switch in
/// _buildExerciseContent built widgets without a key tied to exercise.id.
/// Flutter then reused the old State instead of remounting. The screen now
/// keys every exercise widget on exercise.id so moving on always starts
/// fresh.
void main() {
  testWidgets('typed text does not leak into the next dictation question', (
    tester,
  ) async {
    final lesson = LessonEntity(
      id: 'lesson',
      title: 'Two dictations',
      outcome: 'Can complete this task',
      orderIndex: 0,
      estimatedMinutes: 5,
      xpReward: 10,
      exercises: [
        Exercise(
          id: 'd1',
          type: ExerciseType.fillInBlank,
          uiType: 'dictation',
          phase: 'pre_task',
          question: 'Listen and type',
          correctAnswer: 'first sentence',
        ),
        Exercise(
          id: 'd2',
          type: ExerciseType.fillInBlank,
          uiType: 'dictation',
          phase: 'pre_task',
          question: 'Listen and type',
          correctAnswer: 'second sentence',
        ),
      ],
    );

    final repository = _FakeLearningRepository(lesson);
    final provider = LearningProvider(
      startLessonUseCase: StartLessonUseCase(repository: repository),
      submitAnswerUseCase: SubmitAnswerUseCase(repository: repository),
      completeLessonUseCase: CompleteLessonUseCase(repository: repository),
      getCourseRoadmapUseCase: GetCourseRoadmapUseCase(repository: repository),
      getLessonContentUseCase: GetLessonContentUseCase(repository: repository),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => TtsSettingsProvider()),
        ],
        child: const MaterialApp(
          home: LearningSessionScreen(lessonId: 'lesson', courseId: 'course'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'leftover typed text');
    await tester.pump();
    expect(find.text('leftover typed text'), findsOneWidget);

    provider.nextExercise();
    await tester.pump();

    expect(find.text('leftover typed text'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    provider.dispose();
  });
}

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
  Future<Either<Failure, LessonEntity>> getLessonContent(
    String lessonId,
  ) async => Right(lesson);

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
