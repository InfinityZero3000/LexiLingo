import 'package:lexilingo_app/features/gamification/data/datasources/gamification_remote_data_source.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';

class GamificationRepositoryImpl implements GamificationRepository {
  GamificationRepositoryImpl(this._remote);

  final GamificationRemoteDataSource _remote;

  @override
  Future<WalletEntity> getWallet() async {
    final json = await _remote.getWallet();
    return WalletEntity.fromJson(json);
  }

  @override
  Future<List<WalletTransactionEntity>> getTransactions({int limit = 50}) async {
    final list = await _remote.getTransactions(limit: limit);
    return list.map((e) => WalletTransactionEntity.fromJson(e)).toList();
  }

  @override
  Future<StarterRewardEntity?> getPendingStarterReward() async {
    final json = await _remote.getPendingStarterReward();
    return json != null ? StarterRewardEntity.fromJson(json) : null;
  }

  @override
  Future<bool> acknowledgeStarterReward() => _remote.acknowledgeStarterReward();

  @override
  Future<List<ShopItemEntity>> getShopItems() async {
    final list = await _remote.getShopItems();
    return list.map((e) => ShopItemEntity.fromJson(e)).toList();
  }

  @override
  Future<bool> purchaseItem(String itemId, {int quantity = 1}) =>
      _remote.purchaseItem(itemId, quantity: quantity);

  @override
  Future<List<InventoryItemEntity>> getInventory() async {
    final json = await _remote.getInventory();
    final items = json['items'] as List? ?? [];
    return items.map((e) => InventoryItemEntity.fromJson(e)).toList();
  }

  @override
  Future<bool> useItem(String inventoryId) => _remote.useItem(inventoryId);

  @override
  Future<String?> equipAvatar(String inventoryId) async {
    final json = await _remote.equipAvatar(inventoryId);
    return json?['avatar_url'] as String?;
  }

  @override
  Future<LeaderboardEntity> getLeaderboard(String league) async {
    final json = await _remote.getLeaderboard(league);
    return LeaderboardEntity.fromJson(json);
  }

  @override
  Future<LeagueStatusEntity> getLeagueStatus() async {
    final json = await _remote.getLeagueStatus();
    return LeagueStatusEntity.fromJson(json);
  }
}
