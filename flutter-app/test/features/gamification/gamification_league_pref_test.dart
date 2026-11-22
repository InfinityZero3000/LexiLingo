import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends Fake implements GamificationRepository {
  String league = 'silver';

  @override
  Future<LeagueStatusEntity> getLeagueStatus() async => LeagueStatusEntity(
    league: league,
    currentRank: 1,
    xpEarned: 0,
    lessonsCompleted: 0,
    isInPromotionZone: false,
    isInDemotionZone: false,
    weekEndsInHours: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the last known league is kept per learner', () async {
    final repo = _Repo();
    final provider = GamificationProvider(repository: repo);
    await UserScopeService.setActiveUserId('user-a');
    await provider.loadLeagueStatus();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('u:user-a:lexilingo.last_known_league'), 'silver');
    expect(prefs.containsKey('lexilingo.last_known_league'), isFalse);
  });

  test('another learner\'s league is not a league change', () async {
    final repo = _Repo();
    final provider = GamificationProvider(repository: repo);
    await UserScopeService.setActiveUserId('user-a');
    await provider.loadLeagueStatus();

    provider.reset();
    await UserScopeService.setActiveUserId('user-b');
    repo.league = 'bronze';
    await provider.loadLeagueStatus();

    expect(provider.leagueChangedFrom, isNull);
    expect(provider.leagueChangedTo, isNull);
  });

  test(
    'a quick sign-in after reset is not cleaned out from under it',
    () async {
      final repo = _Repo();
      final provider = GamificationProvider(repository: repo);
      await UserScopeService.setActiveUserId('user-a');
      await provider.loadLeagueStatus();

      provider.reset();
      await UserScopeService.setActiveUserId('user-b');
      await provider.loadLeagueStatus();
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('u:user-b:lexilingo.last_known_league'), 'silver');
      expect(prefs.getString('u:user-a:lexilingo.last_known_league'), 'silver');
    },
  );

  test('the same learner moving league sees the change', () async {
    final repo = _Repo();
    final provider = GamificationProvider(repository: repo);
    await UserScopeService.setActiveUserId('user-a');
    await provider.loadLeagueStatus();

    repo.league = 'gold';
    await provider.loadLeagueStatus();

    expect(provider.leagueChangedFrom, 'silver');
    expect(provider.leagueChangedTo, 'gold');
  });
}
