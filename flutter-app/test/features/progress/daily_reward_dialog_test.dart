import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import 'package:lexilingo_app/features/progress/domain/entities/content_activity_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_reward_dialog.dart';

class _RewardRepository implements ProgressRepository {
  _RewardRepository(this.streak);

  final StreakEntity streak;

  @override
  Future<Either<Failure, StreakEntity>> getMyStreak() async => Right(streak);

  @override
  Future<Either<Failure, Map<String, dynamic>>> claimDailyReward() async =>
      const Right({'gems_awarded': 15});

  @override
  Future<Either<Failure, Map<String, dynamic>>> claimChallengeReward(
    String challengeId,
  ) async => throw UnimplementedError();

  @override
  Future<Either<Failure, LessonCompletionResult>> completeLesson({
    required String lessonId,
    required double score,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, ContentActivityEntity>> getContentActivity({
    int days = 7,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, CourseProgressWithUnits>> getCourseProgress(
    String courseId,
  ) async => throw UnimplementedError();

  @override
  Future<Either<Failure, DailyChallengesResponse>> getDailyChallenges() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, ProgressStatsEntity>> getMyProgress() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> getTotalXp() async => throw UnimplementedError();

  @override
  Future<Either<Failure, WeeklyProgressEntity>> getWeeklyProgress() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, StreakEntity>> restoreStreak() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, StreakUpdateResult>> updateStreak() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Map<String, dynamic>>> useStreakFreeze() async =>
      throw UnimplementedError();
}

StreakEntity _streak({required bool rewardAvailable}) => StreakEntity(
  currentStreak: 3,
  longestStreak: 3,
  totalDaysActive: 3,
  lastActivityDate: DateTime(2026, 11).toIso8601String(),
  freezeCount: 0,
  isActiveToday: true,
  streakAtRisk: false,
  isDailyRewardAvailable: rewardAvailable,
);

Future<StreakProvider> _pumpDialog(
  WidgetTester tester, {
  required bool rewardAvailable,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final provider = StreakProvider(
    repository: _RewardRepository(_streak(rewardAvailable: rewardAvailable)),
  );
  await provider.loadStreak();

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDailyRewardDialog(context, provider),
              child: const Text('Open reward'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open reward'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    EasyLocalization.logger.enableLevels = [];
  });

  testWidgets('uses the gift emblem without the frozen star-burst layer', (
    tester,
  ) async {
    final provider = await _pumpDialog(tester, rewardAvailable: true);
    addTearDown(provider.dispose);

    expect(
      find.byKey(const ValueKey('daily-reward-gift-emblem')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.redeem_rounded), findsOneWidget);
    expect(find.byType(LottieAnimationWidget), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('shows claimed, current, and future reward states', (
    tester,
  ) async {
    final provider = await _pumpDialog(tester, rewardAvailable: true);
    addTearDown(provider.dispose);

    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.diamond_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(4));
  });

  testWidgets('disables claiming when the reward is no longer available', (
    tester,
  ) async {
    final provider = await _pumpDialog(tester, rewardAvailable: false);
    addTearDown(provider.dispose);

    final claimButton = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(claimButton.onPressed, isNull);
  });
}
