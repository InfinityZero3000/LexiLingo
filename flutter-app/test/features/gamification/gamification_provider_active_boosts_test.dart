import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

class _FakeRepository implements GamificationRepository {
  _FakeRepository({required this.items});

  final List<InventoryItemEntity> items;

  @override
  Future<List<InventoryItemEntity>> getInventory() async => items;

  @override
  Future<WalletEntity> getWallet() async => throw UnimplementedError();
  @override
  Future<List<WalletTransactionEntity>> getTransactions({int limit = 50}) async => [];
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
  Future<LeaderboardEntity> getLeaderboard(String league) async =>
      throw UnimplementedError();
  @override
  Future<LeagueStatusEntity> getLeagueStatus() async => throw UnimplementedError();
}

InventoryItemEntity _inventoryItem({
  required String id,
  required bool isActive,
  DateTime? expiresAt,
}) =>
    InventoryItemEntity.fromJson({
      'id': id,
      'item': {
        'id': 'item_$id',
        'name': 'Double XP',
        'description': 'desc',
        'category': 'boosts',
        'price_gems': 50,
        'icon_url': '',
        'effect_type': 'double_xp',
        'effect_duration': 24,
        'effects': {},
        'is_available': true,
      },
      'quantity': 1,
      'is_active': isActive,
      'expires_at': expiresAt?.toIso8601String(),
      'activated_at': isActive ? DateTime.now().toIso8601String() : null,
      'purchased_at': DateTime.now().toIso8601String(),
    });

void main() {
  group('GamificationProvider.activeBoosts', () {
    test('returns empty list when inventory is empty', () async {
      final provider = GamificationProvider(
        repository: _FakeRepository(items: []),
      );

      await provider.loadInventory();
      expect(provider.activeBoosts, isEmpty);
      provider.dispose();
    });

    test('returns only active, non-expired boosts with expiresAt set', () async {
      final futureExpiry = DateTime.now().add(const Duration(hours: 2));
      final pastExpiry = DateTime.now().subtract(const Duration(hours: 1));

      final provider = GamificationProvider(
        repository: _FakeRepository(items: [
          // ✅ Active + not expired + has expiresAt → included
          _inventoryItem(id: 'a', isActive: true, expiresAt: futureExpiry),
          // ✗ Not active
          _inventoryItem(id: 'b', isActive: false),
          // ✗ Active but expired
          _inventoryItem(id: 'c', isActive: true, expiresAt: pastExpiry),
          // ✗ Active but no expiresAt
          _inventoryItem(id: 'd', isActive: true),
        ]),
      );

      await provider.loadInventory();
      expect(provider.activeBoosts.length, 1);
      expect(provider.activeBoosts.first.id, 'a');
      provider.dispose();
    });

    test('remainingDuration is positive for future expiry', () async {
      final futureExpiry = DateTime.now().add(const Duration(hours: 3));

      final provider = GamificationProvider(
        repository: _FakeRepository(items: [
          _inventoryItem(id: 'x', isActive: true, expiresAt: futureExpiry),
        ]),
      );

      await provider.loadInventory();
      final boost = provider.activeBoosts.first;
      expect(boost.remainingDuration, isNotNull);
      expect(boost.remainingDuration!.inSeconds, greaterThan(0));
      provider.dispose();
    });
  });
}
