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
}
