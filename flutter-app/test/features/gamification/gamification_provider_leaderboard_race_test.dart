import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

class _DeferredLeaderboardRepository implements GamificationRepository {
  final Map<String, Completer<LeaderboardEntity>> pending = {};

  @override
  Future<LeaderboardEntity> getLeaderboard(String league) =>
      (pending[league] = Completer<LeaderboardEntity>()).future;

  @override
  Future<List<InventoryItemEntity>> getInventory() async => [];
  @override
  Future<WalletEntity> getWallet() async => throw UnimplementedError();
  @override
  Future<List<WalletTransactionEntity>> getTransactions({
    int limit = 50,
  }) async => [];
  @override
  Future<StarterRewardEntity?> getPendingStarterReward() async => null;
  @override
  Future<bool> acknowledgeStarterReward() async => false;
  @override
  Future<List<ShopItemEntity>> getShopItems() async => [];
  @override
  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async => false;
  @override
  Future<Map<String, dynamic>?> useItem(String inventoryId) async => null;
  @override
  Future<String?> equipAvatar(String inventoryId) async => null;
  @override
  Future<LeagueStatusEntity> getLeagueStatus() async =>
      throw UnimplementedError();
}

LeaderboardEntity _board(String league) => LeaderboardEntity(
  league: league,
  weekStart: DateTime(2026, 1, 5),
  weekEnd: DateTime(2026, 1, 11),
  entries: const [],
);

void main() {
  test(
    'a slow response for a previous league does not change the selection',
    () async {
      final repo = _DeferredLeaderboardRepository();
      final provider = GamificationProvider(repository: repo);

      provider.setLeague('silver');
      provider.setLeague('gold');
      expect(provider.selectedLeague, 'gold');

      repo.pending['gold']!.complete(_board('gold'));
      await Future<void>.delayed(Duration.zero);
      repo.pending['silver']!.complete(_board('silver'));
      await Future<void>.delayed(Duration.zero);

      expect(provider.selectedLeague, 'gold');
      expect(provider.leaderboard?.league, 'gold');
      expect(provider.leaderboardFor('silver')?.league, 'silver');
      provider.dispose();
    },
  );
}
