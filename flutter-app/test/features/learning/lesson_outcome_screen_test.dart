import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/learning/data/models/lesson_complete_model.dart';
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
import 'package:lexilingo_app/features/notifications/domain/services/push_permission_gateway.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DiskAssets extends AssetLoader {
  const _DiskAssets(this.lang);
  final String lang;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('assets/i18n/$lang.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Gateway implements PushPermissionGateway {
  @override
  Future<PushPermission> status() async => PushPermission.granted;

  @override
  Future<PushPermission> requestPermission() async => PushPermission.granted;
}

class _Progress extends Fake implements ProgressRepository {
  @override
  Future<Either<Failure, StreakUpdateResult>> updateStreak() async =>
      const Left(ServerFailure('offline'));
}

Exercise _q(String id) => Exercise(
  id: id,
  type: ExerciseType.multipleChoice,
  uiType: 'multiple_choice',
  question: 'Pick bravo $id',
  options: const ['alpha', 'bravo'],
  correctAnswer: 'bravo',
);

class _Repo implements LearningRepository {
  _Repo(this.outcome);
  final LessonComplete outcome;
  int starts = 0;

  @override
  Future<Either<Failure, LessonAttempt>> startLesson(String lessonId) async {
    starts++;
    return Right(
      LessonAttempt(
        attemptId: 'a$starts',
        lessonId: lessonId,
        startedAt: DateTime(2026),
        totalQuestions: 2,
        livesRemaining: 3,
        hintsAvailable: 3,
      ),
    );
  }

  @override
  Future<Either<Failure, LessonEntity>> getLessonContent(String id) async =>
      Right(
        LessonEntity(
          id: 'lesson',
          title: 'Two',
          outcome: 'x',
          orderIndex: 0,
          estimatedMinutes: 5,
          xpReward: 10,
          exercises: [_q('1'), _q('2')],
        ),
      );

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
      currentScore: 0,
    ),
  );

  @override
  Future<Either<Failure, LessonComplete>> completeLesson(String id) async =>
      Right(outcome);

  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(String id) =>
      throw UnsupportedError('not used');
}

LessonComplete _outcome({
  required bool passed,
  required double score,
  int? passThreshold,
  int xp = 0,
}) => LessonComplete(
  attemptId: 'a1',
  passed: passed,
  passThreshold: passThreshold,
  finalScore: score,
  totalXpEarned: xp,
  timeSpentSeconds: 30,
  accuracy: score,
  starsEarned: 0,
  achievementsUnlocked: const [],
  totalQuestions: 2,
  correctAnswers: 1,
  wrongAnswers: 1,
  hintsUsed: 0,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    if (!sl.isRegistered<PushPermissionGateway>()) {
      sl.registerSingleton<PushPermissionGateway>(_Gateway());
    }
  });

  Future<void> finish(WidgetTester tester, _Repo repo, String lang) async {
    final provider = LearningProvider(
      startLessonUseCase: StartLessonUseCase(repository: repo),
      submitAnswerUseCase: SubmitAnswerUseCase(repository: repo),
      completeLessonUseCase: CompleteLessonUseCase(repository: repo),
      getCourseRoadmapUseCase: GetCourseRoadmapUseCase(repository: repo),
      getLessonContentUseCase: GetLessonContentUseCase(repository: repo),
    );
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => TtsSettingsProvider()),
          ChangeNotifierProvider(
            create: (_) => StreakProvider(repository: _Progress()),
          ),
          ChangeNotifierProvider(
            create: (_) => GamificationProvider(repository: _NoGamification()),
          ),
        ],
        child: EasyLocalization(
          supportedLocales: [Locale(lang)],
          path: 'unused',
          fallbackLocale: Locale(lang),
          startLocale: Locale(lang),
          useOnlyLangCode: true,
          saveLocale: false,
          assetLoader: _DiskAssets(lang),
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: const LearningSessionScreen(
                lessonId: 'lesson',
                courseId: 'course',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('bravo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(lang == 'en' ? 'Continue' : 'Tiếp tục'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('a failed lesson says so, with the lesson pass mark and no XP', (
    tester,
  ) async {
    final repo = _Repo(
      _outcome(passed: false, score: 50, passThreshold: 70, xp: 0),
    );
    await finish(tester, repo, 'en');

    expect(find.text('Not passed yet'), findsOneWidget);
    expect(find.text('You need 70% to pass this lesson.'), findsOneWidget);
    expect(find.text('Well done!'), findsNothing);
    expect(find.text('Excellent!'), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
    expect(find.text('Practice Again'), findsOneWidget);

    await tester.tap(find.text('Practice Again'));
    await tester.pumpAndSettle();
    expect(repo.starts, 2);
  });

  testWidgets('the failed state reads in Vietnamese too', (tester) async {
    await finish(
      tester,
      _Repo(_outcome(passed: false, score: 50, passThreshold: 70)),
      'vi',
    );

    expect(find.text('Chưa đạt'), findsOneWidget);
    expect(find.text('Bạn cần đạt 70% để qua bài học này.'), findsOneWidget);
    expect(find.text('Làm tốt lắm!'), findsNothing);
  });

  testWidgets('a passed lesson keeps its celebration and XP', (tester) async {
    await finish(
      tester,
      _Repo(_outcome(passed: true, score: 100, passThreshold: 70, xp: 25)),
      'en',
    );

    expect(find.text('Not passed yet'), findsNothing);
    expect(find.text('+25 XP'), findsOneWidget);
  });

  test('the model reads pass_threshold and tolerates a missing one', () {
    final base = {'attempt_id': 'a', 'passed': false, 'final_score': 40};
    expect(
      LessonCompleteModel.fromJson({
        ...base,
        'pass_threshold': 65,
      }).passThreshold,
      65,
    );
    expect(LessonCompleteModel.fromJson(base).passThreshold, isNull);
    expect(
      LessonCompleteModel.fromJson({
        'attempt_id': 'a',
        'passed': true,
        'score': 90,
      }).finalScore,
      90,
    );
  });
}

class _NoGamification extends Fake implements GamificationRepository {}
