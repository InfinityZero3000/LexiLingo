import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/unlocked_achievement.dart';
import 'package:lexilingo_app/features/achievements/domain/repositories/achievement_repository.dart';
import 'package:lexilingo_app/features/achievements/presentation/providers/achievement_provider.dart';

class _Repo implements AchievementRepository {
  _Repo({this.fail = false});
  final bool fail;

  @override
  Future<List<AchievementEntity>> getAllAchievements() async {
    if (fail) throw Exception('offline');
    return [];
  }

  @override
  Future<List<UserAchievementEntity>> getMyAchievements() async {
    if (fail) throw Exception('offline');
    return [];
  }

  @override
  Future<List<UnlockedAchievement>> checkAllAchievements() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'an empty API response stays empty instead of showing sample data',
    () async {
      final provider = AchievementProvider(repository: _Repo());
      await provider.loadAll();
      expect(provider.allAchievements, isEmpty);
      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
    },
  );

  test('an API failure sets the error and shows no sample data', () async {
    final provider = AchievementProvider(repository: _Repo(fail: true));
    await provider.loadAll();
    expect(provider.allAchievements, isEmpty);
    expect(provider.error, isNotNull);
    expect(provider.isLoading, isFalse);
  });

  group('integrity', () {
    test(
      'a failed reload keeps the previous list and sets the error',
      () async {
        final repo = _ScriptedRepo();
        final provider = AchievementProvider(repository: repo);
        repo.mine = [_mine('a')];
        await provider.loadMyAchievements();
        expect(provider.myAchievements, hasLength(1));

        repo.failMine = true;
        await provider.loadMyAchievements();

        expect(provider.myAchievements, hasLength(1));
        expect(provider.error, isNotNull);
        expect(provider.isLoading, isFalse);
      },
    );

    test(
      'overlapping loads: the newest call wins even if it finishes first',
      () async {
        final repo = _ScriptedRepo();
        final provider = AchievementProvider(repository: repo);
        final older = Completer<List<UserAchievementEntity>>();
        final newer = Completer<List<UserAchievementEntity>>();
        repo.mineQueue = [older, newer];

        final first = provider.loadMyAchievements();
        final second = provider.loadMyAchievements();
        newer.complete([_mine('new')]);
        await second;
        older.complete([_mine('old')]);
        await first;

        expect(provider.myAchievements.map((e) => e.id), ['new']);
        expect(provider.isLoading, isFalse);
      },
    );

    test(
      'loadAll is not discarded by a loadMyAchievements fired meanwhile',
      () async {
        final repo = _ScriptedRepo();
        final provider = AchievementProvider(repository: repo);
        final all = Completer<List<AchievementEntity>>();
        final mine = Completer<List<UserAchievementEntity>>();
        repo.allQueue = [all];
        final allsMine = Completer<List<UserAchievementEntity>>();
        repo.mineQueue = [allsMine, mine];

        final loadAll = provider.loadAll();
        final loadMine = provider.loadMyAchievements();
        mine.complete([_mine('m')]);
        await loadMine;
        all.complete([_mine('x').achievement]);
        allsMine.complete([_mine('stale')]);
        await loadAll;

        expect(provider.allAchievements.map((e) => e.id), ['x']);
        expect(provider.myAchievements.map((e) => e.id), ['m']);
        expect(provider.isLoading, isFalse);
      },
    );

    test('a late check or unlock after reset leaves no popup behind', () async {
      final repo = _ScriptedRepo();
      final provider = AchievementProvider(repository: repo);
      final check = Completer<List<UnlockedAchievement>>();
      repo.checkResult = check;

      final pending = provider.checkAchievements();
      final epoch = provider.sessionEpoch;
      provider.reset();
      check.complete([_unlocked()]);
      await pending;
      provider.handleUnlockedAchievements([
        _unlockedJson(),
      ], sessionEpoch: epoch);

      expect(provider.recentlyUnlocked, isEmpty);
    });

    test('reset empties the lists and drops an in-flight load', () async {
      final repo = _ScriptedRepo();
      final provider = AchievementProvider(repository: repo);
      repo.mine = [_mine('a')];
      await provider.loadMyAchievements();

      final inFlight = Completer<List<UserAchievementEntity>>();
      repo.mineQueue = [inFlight];
      final load = provider.loadMyAchievements();
      provider.reset();
      inFlight.complete([_mine('previous-account')]);
      await load;

      expect(provider.myAchievements, isEmpty);
      expect(provider.allAchievements, isEmpty);
      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
    });
  });
}

UserAchievementEntity _mine(String id) => UserAchievementEntity(
  id: id,
  achievement: AchievementEntity(
    id: id,
    name: id,
    description: '',
    conditionType: 'x',
    conditionValue: 1,
    category: 'lesson',
    xpReward: 0,
    gemsReward: 0,
    rarity: 'common',
  ),
  unlockedAt: DateTime(2026, 1, 1),
  progress: 1,
);

class _ScriptedRepo implements AchievementRepository {
  List<UserAchievementEntity> mine = [];
  bool failMine = false;
  List<Completer<List<UserAchievementEntity>>> mineQueue = [];
  List<Completer<List<AchievementEntity>>> allQueue = [];
  Completer<List<UnlockedAchievement>>? checkResult;

  @override
  Future<List<UnlockedAchievement>> checkAllAchievements() =>
      checkResult?.future ?? Future.value([]);

  @override
  Future<List<AchievementEntity>> getAllAchievements() =>
      allQueue.isNotEmpty ? allQueue.removeAt(0).future : Future.value([]);

  @override
  Future<List<UserAchievementEntity>> getMyAchievements() {
    if (mineQueue.isNotEmpty) return mineQueue.removeAt(0).future;
    if (failMine) return Future.error(Exception('offline'));
    return Future.value(mine);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UnlockedAchievement _unlocked() => const UnlockedAchievement(
  id: 'u',
  name: 'u',
  description: '',
  category: 'lesson',
  rarity: 'common',
  xpReward: 0,
  gemsReward: 0,
);

Map<String, dynamic> _unlockedJson() => {
  'id': 'u',
  'name': 'u',
  'description': '',
  'category': 'lesson',
  'rarity': 'common',
  'xp_reward': 0,
  'gems_reward': 0,
};
