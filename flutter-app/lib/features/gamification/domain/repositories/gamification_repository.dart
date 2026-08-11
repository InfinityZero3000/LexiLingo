import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';

abstract class GamificationRepository {
  Future<WalletEntity> getWallet();
  Future<List<WalletTransactionEntity>> getTransactions({int limit = 50});
  Future<StarterRewardEntity?> getPendingStarterReward();
  Future<bool> acknowledgeStarterReward();
  Future<List<ShopItemEntity>> getShopItems();
  Future<bool> purchaseItem(String itemId, {int quantity = 1});
  Future<List<InventoryItemEntity>> getInventory();
  /// Uses an inventory item; returns its applied effects payload on
  /// success, or null on failure.
  Future<Map<String, dynamic>?> useItem(String inventoryId);
  Future<String?> equipAvatar(String inventoryId);
  Future<LeaderboardEntity> getLeaderboard(String league);
  Future<LeagueStatusEntity> getLeagueStatus();
}
