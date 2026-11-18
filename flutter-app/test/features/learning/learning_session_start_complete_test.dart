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

void main() {
  late _FakeRepository repository;
  late LearningProvider provider;

  setUp(() {
    repository = _FakeRepository();
    provider = LearningProvider(
      startLessonUseCase: StartLessonUseCase(repository: repository),
      submitAnswerUseCase: SubmitAnswerUseCase(repository: repository),
      completeLessonUseCase: CompleteLessonUseCase(repository: repository),
      getCourseRoadmapUseCase: GetCourseRoadmapUseCase(repository: repository),
      getLessonContentUseCase: GetLessonContentUseCase(repository: repository),
    );
  });

  tearDown(() => provider.dispose());

  Future<void> finishLesson() async {
    await provider.startLesson('course', 'lesson');
    await provider.submitAnswer('b');
    provider.nextExercise();
    await pumpEventQueue();
  }

  test(
    'a locked 409 on start sets the locked flag and loads no content',
    () async {
      repository.startResult = const Left(
        ConflictFailure('Lesson is locked: complete the previous lesson first'),
      );

      await provider.startLesson('course', 'lesson');

      expect(provider.isLessonLocked, isTrue);
      expect(provider.isContentUnavailable, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.currentLesson, isNull);
      expect(repository.contentCalls, 0);
    },
  );

  test(
    'a missing-exercises 409 on start is content-unavailable, not locked',
    () async {
      repository.startResult = const Left(
        ConflictFailure('Lesson content is missing exercises'),
      );

      await provider.startLesson('course', 'lesson');

      expect(provider.isContentUnavailable, isTrue);
      expect(provider.isLessonLocked, isFalse);
      expect(provider.currentLesson, isNull);
      expect(repository.contentCalls, 0);
    },
  );

  test(
    'any other start failure stops play and leaves a retryable error',
    () async {
      repository.startResult = const Left(NetworkFailure('offline'));

      await provider.startLesson('course', 'lesson');

      expect(provider.error, 'offline');
      expect(provider.isContentUnavailable, isFalse);
      expect(provider.isLessonLocked, isFalse);
      expect(provider.currentLesson, isNull);
      expect(provider.currentAttempt, isNull);

      repository.startResult = null;
      await provider.startLesson('course', 'lesson');

      expect(provider.error, isNull);
      expect(provider.currentLesson, isNotNull);
    },
  );

  test(
    'a failed complete shows no XP and can be retried for the same attempt',
    () async {
      repository.completeResults.add(const Left(NetworkFailure('offline')));
      await finishLesson();

      expect(provider.completionFailed, isTrue);
      expect(provider.lessonResult, isNull);
      expect(provider.xpEarned, 0);

      await provider.retryCompletion();

      expect(provider.completionFailed, isFalse);
      expect(provider.lessonResult?.totalXpEarned, 25);
      expect(provider.xpEarned, 25);
      expect(repository.completedAttemptIds, ['attempt', 'attempt']);
    },
  );

  test('practice again starts a fresh attempt and completes it', () async {
    await finishLesson();
    repository.nextAttemptId = 'attempt-2';

    await provider.restartLesson();
    await provider.submitAnswer('b');
    provider.nextExercise();
    await pumpEventQueue();

    expect(repository.startCalls, 2);
    expect(provider.currentAttempt?.attemptId, 'attempt-2');
    expect(repository.completedAttemptIds, ['attempt', 'attempt-2']);
    expect(provider.lessonResult?.totalXpEarned, 25);
  });

  test('a lesson whose content has no exercises is not playable', () async {
    repository.exercisesOverride = const [];

    await provider.startLesson('course', 'lesson');

    expect(provider.isContentUnavailable, isTrue);
    expect(provider.currentLesson, isNull);
    expect(provider.isCompleted, isFalse);
  });

  test('progress counts answered questions, not the one on screen', () async {
    await provider.startLesson('course', 'lesson');
    expect(provider.progress, 0);

    await provider.submitAnswer('b');
    expect(provider.progress, 1);

    provider.nextExercise();
    await pumpEventQueue();
    expect(provider.progress, 1);
  });

  test('advancing past the last question completes only once', () async {
    await finishLesson();
    provider.nextExercise();
    provider.skipExercise();
    await pumpEventQueue();

    expect(provider.currentExerciseIndex, 1);
    expect(repository.completedAttemptIds, ['attempt']);
  });

  test(
    'retry after an older server already saved it is not an error',
    () async {
      repository.completeResults
        ..add(const Left(NetworkFailure('offline')))
        ..add(const Left(ValidationFailure('Already completed')));
      await finishLesson();

      await provider.retryCompletion();

      expect(provider.completionFailed, isFalse);
      expect(provider.lessonResult, isNull);
    },
  );
}

Exercise _mc(String id) => Exercise(
  id: id,
  type: ExerciseType.multipleChoice,
  uiType: 'multiple_choice',
  question: 'Pick b',
  options: const ['a', 'b'],
  correctAnswer: 'b',
);

class _FakeRepository implements LearningRepository {
  Either<Failure, LessonAttempt>? startResult;
  final completeResults = <Either<Failure, LessonComplete>>[];
  final completedAttemptIds = <String>[];
  int contentCalls = 0;
  int startCalls = 0;
  String nextAttemptId = 'attempt';

  List<Exercise>? exercisesOverride;

  LessonEntity get lesson => LessonEntity(
    id: 'lesson',
    title: 'One question',
    outcome: 'Can complete this task',
    orderIndex: 0,
    estimatedMinutes: 5,
    xpReward: 10,
    exercises: exercisesOverride ?? [_mc('q1')],
  );

  @override
  Future<Either<Failure, LessonAttempt>> startLesson(String lessonId) async {
    startCalls++;
    return startResult ??
        Right(
          LessonAttempt(
            attemptId: nextAttemptId,
            lessonId: lessonId,
            startedAt: DateTime(2026),
            totalQuestions: 1,
            livesRemaining: 3,
            hintsAvailable: 3,
          ),
        );
  }

  @override
  Future<Either<Failure, LessonEntity>> getLessonContent(
    String lessonId,
  ) async {
    contentCalls++;
    return Right(lesson);
  }

  @override
  Future<Either<Failure, AnswerResponse>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String questionType,
    required dynamic userAnswer,
    required int timeSpentMs,
    bool hintUsed = false,
    double? confidenceScore,
  }) async => const Right(
    AnswerResponse(
      questionAttemptId: 'qa',
      isCorrect: true,
      xpEarned: 0,
      livesRemaining: 3,
      hintsRemaining: 3,
      currentScore: 100,
    ),
  );

  @override
  Future<Either<Failure, LessonComplete>> completeLesson(
    String attemptId,
  ) async {
    completedAttemptIds.add(attemptId);
    if (completeResults.isNotEmpty) return completeResults.removeAt(0);
    return const Right(
      LessonComplete(
        attemptId: 'attempt',
        passed: true,
        finalScore: 100,
        totalXpEarned: 25,
        timeSpentSeconds: 5,
        accuracy: 100,
        starsEarned: 3,
        achievementsUnlocked: [],
        totalQuestions: 1,
        correctAnswers: 1,
        wrongAnswers: 0,
        hintsUsed: 0,
      ),
    );
  }

  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(String courseId) =>
      throw UnsupportedError('not used');
}
