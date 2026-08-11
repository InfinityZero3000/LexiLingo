import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

class _FakeRepository implements GamificationRepository {
  _FakeRepository({required this.items, this.useItemEffects});

  final List<InventoryItemEntity> items;

  /// When set, `useItem` returns this payload and succeeds; null = failure.
  final Map<String, dynamic>? useItemEffects;
  String? lastUsedInventoryId;

  @override
  Future<List<InventoryItemEntity>> getInventory() async => items;

  @override
  Future<Map<String, dynamic>?> useItem(String inventoryId) async {
    lastUsedInventoryId = inventoryId;
    return useItemEffects;
  }

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
  Future<String?> equipAvatar(String inventoryId) async => null;
  @override
  Future<LeaderboardEntity> getLeaderboard(String league) async =>
      throw UnimplementedError();
  @override
  Future<LeagueStatusEntity> getLeagueStatus() async =>
      throw UnimplementedError();
}

InventoryItemEntity _powerUpItem({
  required String id,
  required String itemType,
  required int quantity,
}) => InventoryItemEntity.fromJson({
  'id': id,
  'item': {
    'id': 'item_$id',
    'name': 'Test Power-Up',
    'description': 'desc',
    'category': 'power_ups',
    'price_gems': 10,
    'icon_url': '',
    'effect_type': itemType,
    'effects': {'seconds': 10},
    'is_available': true,
  },
  'quantity': quantity,
  'is_active': false,
  'purchased_at': DateTime.now().toIso8601String(),
});

void main() {
  group('GamificationProvider.powerUpsOf', () {
    test('returns only owned items matching the requested item type', () async {
      final provider = GamificationProvider(
        repository: _FakeRepository(
          items: [
            _powerUpItem(
              id: 'a',
              itemType: ShopItemEntity.effectTimeFreeze,
              quantity: 2,
            ),
            _powerUpItem(
              id: 'b',
              itemType: ShopItemEntity.effectSkipToken,
              quantity: 1,
            ),
          ],
        ),
      );

      await provider.loadInventory();
      final timeFreezes = provider.powerUpsOf(ShopItemEntity.effectTimeFreeze);
      expect(timeFreezes.length, 1);
      expect(timeFreezes.first.id, 'a');
      provider.dispose();
    });

    test('excludes owned items with zero quantity', () async {
      final provider = GamificationProvider(
        repository: _FakeRepository(
          items: [
            _powerUpItem(
              id: 'a',
              itemType: ShopItemEntity.effectMistakeShield,
              quantity: 0,
            ),
          ],
        ),
      );

      await provider.loadInventory();
      expect(provider.powerUpsOf(ShopItemEntity.effectMistakeShield), isEmpty);
      provider.dispose();
    });
  });

  group('GamificationProvider.useItemWithEffects', () {
    test('returns the effects payload and refreshes inventory on success', () async {
      final repository = _FakeRepository(
        items: [
          _powerUpItem(
            id: 'a',
            itemType: ShopItemEntity.effectTimeFreeze,
            quantity: 1,
          ),
        ],
        useItemEffects: {'seconds': 10, 'item_type': 'time_freeze'},
      );
      final provider = GamificationProvider(repository: repository);

      await provider.loadInventory();
      final effects = await provider.useItemWithEffects('a');

      expect(effects, isNotNull);
      expect(effects!['seconds'], 10);
      expect(repository.lastUsedInventoryId, 'a');
      provider.dispose();
    });

    test('returns null when the repository reports failure', () async {
      final provider = GamificationProvider(
        repository: _FakeRepository(items: [], useItemEffects: null),
      );

      final effects = await provider.useItemWithEffects('missing');
      expect(effects, isNull);
      provider.dispose();
    });

    test('useItem (legacy bool API) reflects success/failure of the new path', () async {
      final successProvider = GamificationProvider(
        repository: _FakeRepository(items: [], useItemEffects: {}),
      );
      expect(await successProvider.useItem('a'), isTrue);
      successProvider.dispose();

      final failureProvider = GamificationProvider(
        repository: _FakeRepository(items: [], useItemEffects: null),
      );
      expect(await failureProvider.useItem('a'), isFalse);
      failureProvider.dispose();
    });
  });
}
