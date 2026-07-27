import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

class _FakeRepository implements GamificationRepository {
  _FakeRepository({this.starterReward});

  final StarterRewardEntity? starterReward;
  int getPendingStarterRewardCallCount = 0;

  @override
  Future<StarterRewardEntity?> getPendingStarterReward() async {
    getPendingStarterRewardCallCount++;
    return starterReward;
  }

  @override
  Future<bool> acknowledgeStarterReward() async => true;

  @override
  Future<WalletEntity> getWallet() async => throw UnimplementedError();
  @override
  Future<List<WalletTransactionEntity>> getTransactions({int limit = 50}) async => [];
  @override
  Future<List<ShopItemEntity>> getShopItems() async => [];
  @override
  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async => false;
  @override
  Future<List<InventoryItemEntity>> getInventory() async => [];
  @override
  Future<Map<String, dynamic>?> useItem(String inventoryId) async => null;
  @override
  Future<String?> equipAvatar(String inventoryId) async => null;
  @override
  Future<LeaderboardEntity> getLeaderboard(String league) async =>
      throw UnimplementedError();
  @override
  Future<LeagueStatusEntity> getLeagueStatus() async => throw UnimplementedError();
}

void main() {
  test('does not request starter reward when rollout is disabled', () async {
    final repo = _FakeRepository(starterReward: null);
    final provider = GamificationProvider(
      repository: repo,
      enableStarterReward: false,
    );

    final reward = await provider.loadPendingStarterReward();

    expect(reward, isNull);
    expect(repo.getPendingStarterRewardCallCount, 0);
    provider.dispose();
  });

  test('loads starter reward when rollout is enabled', () async {
    final fakeReward = StarterRewardEntity(
      rewardKey: 'new_user_starter_gems_v1',
      gemsAwarded: 100,
      currentBalance: 100,
      title: 'Welcome gift',
      body: '100 Gems have been added to your wallet.',
    );
    final repo = _FakeRepository(starterReward: fakeReward);
    final provider = GamificationProvider(
      repository: repo,
      enableStarterReward: true,
    );

    final reward = await provider.loadPendingStarterReward();

    expect(reward?.gemsAwarded, 100);
    expect(provider.pendingStarterReward?.currentBalance, 100);
    expect(repo.getPendingStarterRewardCallCount, 1);
    provider.dispose();
  });
}
