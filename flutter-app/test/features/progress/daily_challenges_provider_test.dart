import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/data/models/daily_challenge_model.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';

class _Repo implements ProgressRepository {
  _Repo(this.response, {this.bonusFailure});

  DailyChallengesResponse response;
  final Failure? bonusFailure;
  int bonusCalls = 0;

  @override
  Future<Either<Failure, DailyChallengesResponse>> getDailyChallenges() async =>
      Right(response);

  @override
  Future<Either<Failure, Map<String, dynamic>>> claimDailyBonus() async {
    bonusCalls += 1;
    final failure = bonusFailure;
    return failure == null ? const Right({'xp_reward': 50}) : Left(failure);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _json({
  required bool completed,
  bool claimed = false,
  bool bonusClaimed = false,
}) => {
  'date': '2026-11-10',
  'total_completed': completed ? 1 : 0,
  'total_challenges': 1,
  'bonus_xp': 50,
  'bonus_claimed': bonusClaimed,
  'challenges': [
    {
      'id': 'complete_lessons',
      'title': 'Lesson Master',
      'description': 'Complete 1 lesson',
      'icon': 'book',
      'category': 'lesson',
      'target': 1,
      'current': completed ? 1 : 0,
      'xp_reward': 20,
      'is_completed': completed,
      'is_claimed': claimed,
      'expires_at': '2026-11-11T00:00:00',
    },
  ],
};

void main() {
  test('model reads is_claimed and bonus_claimed from the server', () {
    final r = DailyChallengesResponseModel.fromJson(
      _json(completed: true, claimed: true, bonusClaimed: true),
    );
    expect(r.challenges.single.isClaimed, isTrue);
    expect(r.bonusClaimed, isTrue);
  });

  test(
    'a reward claimed earlier today still shows as claimed after reload',
    () async {
      final repo = _Repo(
        DailyChallengesResponseModel.fromJson(
          _json(completed: true, claimed: true),
        ),
      );
      final provider = DailyChallengesProvider(repository: repo);
      await provider.loadChallenges();

      expect(provider.isRewardClaimed('complete_lessons'), isTrue);
    },
  );

  test('claimBonus is refused until every challenge is complete', () async {
    final repo = _Repo(
      DailyChallengesResponseModel.fromJson(_json(completed: false)),
    );
    final provider = DailyChallengesProvider(repository: repo);
    await provider.loadChallenges();

    expect(await provider.claimBonus(), isFalse);
    expect(repo.bonusCalls, 0);
  });

  test('claimBonus calls the API once and marks the bonus claimed', () async {
    final repo = _Repo(
      DailyChallengesResponseModel.fromJson(_json(completed: true)),
    );
    final provider = DailyChallengesProvider(repository: repo);
    await provider.loadChallenges();

    expect(provider.bonusClaimed, isFalse);
    expect(await provider.claimBonus(), isTrue);
    expect(provider.bonusClaimed, isTrue);
    expect(await provider.claimBonus(), isFalse);
    expect(repo.bonusCalls, 1);
  });

  test(
    'a failed bonus claim leaves it claimable and surfaces the error',
    () async {
      final repo = _Repo(
        DailyChallengesResponseModel.fromJson(_json(completed: true)),
        bonusFailure: ServerFailure('boom'),
      );
      final provider = DailyChallengesProvider(repository: repo);
      await provider.loadChallenges();

      expect(await provider.claimBonus(), isFalse);
      expect(provider.bonusClaimed, isFalse);
      expect(provider.errorMessage, 'boom');
    },
  );
}
