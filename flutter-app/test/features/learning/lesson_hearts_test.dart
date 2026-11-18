import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
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
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_hearts_row.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/out_of_hearts_sheet.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EnglishFromDisk extends AssetLoader {
  const _EnglishFromDisk();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('assets/i18n/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

Widget _localized(Widget home, {List<SingleChildWidget>? providers}) {
  final app = EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'unused',
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    useOnlyLangCode: true,
    saveLocale: false,
    assetLoader: const _EnglishFromDisk(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        home: home,
      ),
    ),
  );
  return providers == null
      ? app
      : MultiProvider(providers: providers, child: app);
}

Exercise _mc(String id) => Exercise(
  id: id,
  type: ExerciseType.multipleChoice,
  uiType: 'multiple_choice',
  question: 'Pick b $id',
  options: const ['alpha', 'bravo'],
  correctAnswer: 'bravo',
);

class _LearningRepo implements LearningRepository {
  final lesson = LessonEntity(
    id: 'lesson',
    title: 'Two questions',
    outcome: 'Can do it',
    orderIndex: 0,
    estimatedMinutes: 5,
    xpReward: 10,
    exercises: [_mc('q1'), _mc('q2')],
  );
  Either<Failure, AnswerResponse> answer = const Right(
    AnswerResponse(
      questionAttemptId: 'qa',
      isCorrect: false,
      xpEarned: 0,
      livesRemaining: 0,
      hintsRemaining: 3,
      currentScore: 0,
    ),
  );
  int startCalls = 0;
  int submitCalls = 0;

  @override
  Future<Either<Failure, LessonAttempt>> startLesson(String lessonId) async {
    startCalls++;
    return Right(
      LessonAttempt(
        attemptId: 'attempt$startCalls',
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
  }) async {
    submitCalls++;
    return answer;
  }

  @override
  Future<Either<Failure, LessonComplete>> completeLesson(String id) =>
      throw UnsupportedError('not used');

  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(String id) =>
      throw UnsupportedError('not used');
}

ShopItemEntity _refillItem() => const ShopItemEntity(
  id: 'shop-heart',
  name: 'Heart Refill',
  description: 'x',
  category: ShopItemEntity.categoryPowerUps,
  priceGems: 15,
  iconUrl: '',
  effectType: ShopItemEntity.effectHeartRefill,
);

class _GamificationRepo implements GamificationRepository {
  _GamificationRepo({this.gems = 40});

  int gems;
  bool useOk = true;
  final inventory = <InventoryItemEntity>[];
  int purchases = 0;
  int uses = 0;

  @override
  Future<WalletEntity> getWallet() async =>
      WalletEntity(id: 'w', userId: 'u', gems: gems);

  @override
  Future<List<ShopItemEntity>> getShopItems() async => [_refillItem()];

  @override
  Future<List<InventoryItemEntity>> getInventory() async => List.of(inventory);

  @override
  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async {
    purchases++;
    gems -= 15;
    inventory.add(
      InventoryItemEntity(
        id: 'inv$purchases',
        item: _refillItem(),
        quantity: 1,
        purchasedAt: DateTime(2026),
      ),
    );
    return true;
  }

  @override
  Future<Map<String, dynamic>?> useItem(String inventoryId, {String? gameSessionId}) async {
    uses++;
    if (!useOk) return null;
    inventory.clear();
    return {'hearts_restored': 3};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

LearningProvider _learningProvider(_LearningRepo repo) => LearningProvider(
  startLessonUseCase: StartLessonUseCase(repository: repo),
  submitAnswerUseCase: SubmitAnswerUseCase(repository: repo),
  completeLessonUseCase: CompleteLessonUseCase(repository: repo),
  getCourseRoadmapUseCase: GetCourseRoadmapUseCase(repository: repo),
  getLessonContentUseCase: GetLessonContentUseCase(repository: repo),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  group('LessonHeartsRow', () {
    testWidgets('draws filled and empty hearts with a spoken count', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _localized(const Scaffold(body: LessonHeartsRow(lives: 2))),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Hearts left: 2'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('fits a 320px header next to the progress bar', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _localized(
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: LinearProgressIndicator(value: 0.5)),
                  SizedBox(width: 12),
                  LessonHeartsRow(lives: 3),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('OutOfHeartsSheet', () {
    Future<OutOfHeartsChoice?> open(
      WidgetTester tester, {
      required int? price,
      required int gems,
      Future<bool> Function()? onRefill,
    }) async {
      OutOfHeartsChoice? result;
      await tester.pumpWidget(
        _localized(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showOutOfHeartsSheet(
                    context,
                    refillPrice: price,
                    gems: gems,
                    onRefill: onRefill ?? () async => true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('offers refill, try again and leave', (tester) async {
      await open(tester, price: 15, gems: 40);

      expect(find.text("You're out of hearts"), findsOneWidget);
      expect(find.text('Refill hearts — 15 gems'), findsOneWidget);
      expect(find.text('Try this lesson again'), findsOneWidget);
      expect(find.text('Leave lesson'), findsOneWidget);
      final refill = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Refill hearts — 15 gems'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(refill.onPressed, isNotNull);
    });

    testWidgets('disables refill when gems fall short of the price', (
      tester,
    ) async {
      await open(tester, price: 15, gems: 10);

      final refill = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Refill hearts — 15 gems'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(refill.onPressed, isNull);
      expect(find.textContaining('You need 15 gems'), findsOneWidget);
      expect(find.text('Try this lesson again'), findsOneWidget);
    });

    testWidgets('hides refill when the catalog has no heart refill', (
      tester,
    ) async {
      await open(tester, price: null, gems: 99);

      expect(find.textContaining('Refill hearts'), findsNothing);
      expect(find.text('Leave lesson'), findsOneWidget);
    });

    testWidgets('a failed purchase shows an error and keeps other options', (
      tester,
    ) async {
      await open(tester, price: 15, gems: 40, onRefill: () async => false);

      await tester.tap(find.text('Refill hearts — 15 gems'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('refill_error')), findsOneWidget);
      expect(find.text("You're out of hearts"), findsOneWidget);
      final retry = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Try this lesson again'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(retry.onPressed, isNotNull);
    });
  });

  group('LearningProvider hearts', () {
    late _LearningRepo repo;
    late LearningProvider provider;

    setUp(() {
      repo = _LearningRepo();
      provider = _learningProvider(repo);
    });
    tearDown(() => provider.dispose());

    test(
      'the answer that takes the last heart is graded, then play stops',
      () async {
        await provider.startLesson('course', 'lesson');
        await provider.submitAnswer('alpha');

        expect(provider.livesRemaining, 0);
        expect(provider.isCurrentCorrect, isFalse);
        expect(provider.isOutOfHearts, isTrue);

        provider.nextExercise();
        final prompts = provider.outOfHeartsPromptCount;
        await provider.submitAnswer('bravo');

        expect(repo.submitCalls, 1);
        expect(provider.isCurrentAnswered, isFalse);
        expect(provider.outOfHeartsPromptCount, prompts + 1);
      },
    );

    test(
      'a server out_of_hearts refusal clears the answer and prompts',
      () async {
        await provider.startLesson('course', 'lesson');
        repo.answer = const Left(ConflictFailure(outOfHeartsCode));

        await provider.submitAnswer('bravo');

        expect(provider.isCurrentAnswered, isFalse);
        expect(provider.isCurrentCorrect, isNull);
        expect(provider.livesRemaining, 0);
        expect(provider.outOfHeartsPromptCount, 1);
      },
    );

    test('heartsRefilled restores a full set and answers work again', () async {
      await provider.startLesson('course', 'lesson');
      await provider.submitAnswer('alpha');
      provider.nextExercise();

      provider.heartsRefilled();
      repo.answer = const Right(
        AnswerResponse(
          questionAttemptId: 'qa',
          isCorrect: true,
          xpEarned: 10,
          livesRemaining: 3,
          hintsRemaining: 3,
          currentScore: 50,
        ),
      );
      await provider.submitAnswer('bravo');

      expect(provider.livesRemaining, 3);
      expect(provider.isOutOfHearts, isFalse);
      expect(provider.isCurrentCorrect, isTrue);
    });

    test('restartLesson starts a new attempt with three hearts', () async {
      await provider.startLesson('course', 'lesson');
      await provider.submitAnswer('alpha');
      expect(provider.livesRemaining, 0);

      await provider.restartLesson();

      expect(repo.startCalls, 2);
      expect(provider.currentAttempt!.attemptId, 'attempt2');
      expect(provider.livesRemaining, 3);
      expect(provider.currentExerciseIndex, 0);
    });
  });

  group('GamificationProvider.refillLessonHearts', () {
    test('buys with the catalog price and applies the refill', () async {
      final repo = _GamificationRepo(gems: 40);
      final provider = GamificationProvider(repository: repo);
      await provider.prepareHeartRefill();

      expect(provider.heartRefillItem!.priceGems, 15);
      expect(await provider.refillLessonHearts(), isTrue);
      expect(repo.purchases, 1);
      expect(repo.uses, 1);
      expect(provider.gems, 25);
    });

    test('refuses without enough gems and charges nothing', () async {
      final repo = _GamificationRepo(gems: 14);
      final provider = GamificationProvider(repository: repo);
      await provider.prepareHeartRefill();

      expect(await provider.refillLessonHearts(), isFalse);
      expect(repo.purchases, 0);
    });

    test('an owned refill is applied without a second charge', () async {
      final repo = _GamificationRepo(gems: 40)..useOk = false;
      final provider = GamificationProvider(repository: repo);
      await provider.prepareHeartRefill();

      expect(await provider.refillLessonHearts(), isFalse);
      expect(repo.purchases, 1);

      repo.useOk = true;
      expect(await provider.refillLessonHearts(), isTrue);
      expect(repo.purchases, 1);
      expect(repo.uses, 2);
    });
  });

  group('LearningSessionScreen out of hearts', () {
    late _LearningRepo repo;
    late _GamificationRepo gamificationRepo;
    late LearningProvider provider;

    Future<void> pumpSession(WidgetTester tester) async {
      repo = _LearningRepo();
      gamificationRepo = _GamificationRepo(gems: 40);
      provider = _learningProvider(repo);
      await tester.pumpWidget(
        _localized(
          const LearningSessionScreen(lessonId: 'lesson', courseId: 'course'),
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider(create: (_) => TtsSettingsProvider()),
            ChangeNotifierProvider(
              create: (_) => GamificationProvider(repository: gamificationRepo),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> loseLastHeart(WidgetTester tester) async {
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows hearts and raises the sheet when Continue is pressed', (
      tester,
    ) async {
      await pumpSession(tester);
      expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(3));

      await loseLastHeart(tester);

      expect(find.byIcon(Icons.favorite_border_rounded), findsNWidgets(3));
      expect(find.text("You're out of hearts"), findsOneWidget);
      expect(provider.currentExerciseIndex, 0);
    });

    testWidgets('Try this lesson again restarts the lesson', (tester) async {
      await pumpSession(tester);
      await loseLastHeart(tester);

      await tester.tap(find.text('Try this lesson again'));
      await tester.pumpAndSettle();

      expect(repo.startCalls, 2);
      expect(provider.livesRemaining, 3);
      expect(find.text("You're out of hearts"), findsNothing);
    });

    testWidgets('refill continues the same attempt with three hearts', (
      tester,
    ) async {
      await pumpSession(tester);
      await loseLastHeart(tester);

      await tester.tap(find.text('Refill hearts — 15 gems'));
      await tester.pumpAndSettle();

      expect(repo.startCalls, 1);
      expect(gamificationRepo.purchases, 1);
      expect(provider.livesRemaining, 3);
      expect(provider.currentExerciseIndex, 1);
      expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(3));
    });

    testWidgets('dismissing the sheet does not strand the learner', (
      tester,
    ) async {
      await pumpSession(tester);
      await loseLastHeart(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text("You're out of hearts"), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text("You're out of hearts"), findsOneWidget);
    });
  });
}
