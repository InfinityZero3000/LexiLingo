import 'dart:async';

import 'package:dartz/dartz.dart';
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

/// Skip stays tappable after answering and while the answer is in flight.
/// It used to overwrite a correct result with a miss, and a late response
/// landed on whichever question the index had moved to.
void main() {
  late _FakeLearningRepository repository;
  late LearningProvider provider;

  setUp(() async {
    repository = _FakeLearningRepository();
    provider = LearningProvider(
      startLessonUseCase: StartLessonUseCase(repository: repository),
      submitAnswerUseCase: SubmitAnswerUseCase(repository: repository),
      completeLessonUseCase: CompleteLessonUseCase(repository: repository),
      getCourseRoadmapUseCase: GetCourseRoadmapUseCase(repository: repository),
      getLessonContentUseCase: GetLessonContentUseCase(repository: repository),
    );
    await provider.startLesson('course', 'lesson');
  });

  tearDown(() => provider.dispose());

  test('skip after a correct answer keeps it correct', () async {
    final pending = provider.submitAnswer('b');
    repository.respond(isCorrect: true);
    await pending;
    expect(provider.isCurrentCorrect, isTrue);

    provider.skipExercise();

    expect(provider.score, 1);
    expect(provider.currentExercise?.id, 'q2');
  });

  test('a late response is recorded on the question it answers', () async {
    final pending = provider.submitAnswer('b');
    provider.skipExercise(); // moves on while the request is in flight
    repository.respond(isCorrect: true);
    await pending;

    expect(provider.currentExercise?.id, 'q2');
    expect(provider.isCurrentAnswered, isFalse);
    expect(provider.isCurrentCorrect, isNull);
    expect(provider.score, 1);
  });
}

Exercise _mc(String id) => Exercise(
  id: id,
  type: ExerciseType.multipleChoice,
  uiType: 'multiple_choice',
  question: 'Pick b',
  options: const ['a', 'b'],
  correctAnswer: 'b',
);

class _FakeLearningRepository implements LearningRepository {
  final lesson = LessonEntity(
    id: 'lesson',
    title: 'Three questions',
    outcome: 'Can complete this task',
    orderIndex: 0,
    estimatedMinutes: 5,
    xpReward: 10,
    exercises: [_mc('q1'), _mc('q2'), _mc('q3')],
  );
  Completer<Either<Failure, AnswerResponse>>? _pending;

  void respond({required bool isCorrect}) => _pending!.complete(
    Right(
      AnswerResponse(
        questionAttemptId: 'qa',
        isCorrect: isCorrect,
        xpEarned: 0,
        livesRemaining: 3,
        hintsRemaining: 3,
        currentScore: 0,
      ),
    ),
  );

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
  }) => (_pending = Completer()).future;

  @override
  Future<Either<Failure, LessonComplete>> completeLesson(String attemptId) =>
      throw UnsupportedError('completeLesson is not used by this test');

  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(String courseId) =>
      throw UnsupportedError('getCourseRoadmap is not used by this test');
}
