import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_powerup_tray.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

class _FakeRepository implements GamificationRepository {
  _FakeRepository({this.items = const [], this.useItemEffects});

  final List<InventoryItemEntity> items;
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

Widget _wrap(GamificationProvider provider, Widget child) =>
    MaterialApp(
      home: ChangeNotifierProvider<GamificationProvider>.value(
        value: provider,
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('renders nothing when no power-ups are owned', (tester) async {
    final provider = GamificationProvider(repository: _FakeRepository());
    await provider.loadInventory();

    await tester.pumpWidget(
      _wrap(
        provider,
        GamePowerUpTray(
          availableTypes: const [ShopItemEntity.effectTimeFreeze],
          onUse: (_, __) {},
        ),
      ),
    );

    expect(find.byType(SizedBox), findsWidgets);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('shows the owned quantity badge for an available power-up', (
    tester,
  ) async {
    final provider = GamificationProvider(
      repository: _FakeRepository(
        items: [
          _powerUpItem(
            id: 'a',
            itemType: ShopItemEntity.effectTimeFreeze,
            quantity: 3,
          ),
        ],
      ),
    );
    await provider.loadInventory();

    await tester.pumpWidget(
      _wrap(
        provider,
        GamePowerUpTray(
          availableTypes: const [ShopItemEntity.effectTimeFreeze],
          onUse: (_, __) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('omits power-up types that are owned but not in availableTypes', (
    tester,
  ) async {
    final provider = GamificationProvider(
      repository: _FakeRepository(
        items: [
          _powerUpItem(
            id: 'a',
            itemType: ShopItemEntity.effectSkipToken,
            quantity: 1,
          ),
        ],
      ),
    );
    await provider.loadInventory();

    await tester.pumpWidget(
      _wrap(
        provider,
        GamePowerUpTray(
          availableTypes: const [ShopItemEntity.effectTimeFreeze],
          onUse: (_, __) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1'), findsNothing);
  });

  testWidgets('tapping a power-up calls onUse with the effects payload', (
    tester,
  ) async {
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

    String? usedType;
    Map<String, dynamic>? usedEffects;

    await tester.pumpWidget(
      _wrap(
        provider,
        GamePowerUpTray(
          availableTypes: const [ShopItemEntity.effectTimeFreeze],
          onUse: (type, effects) {
            usedType = type;
            usedEffects = effects;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(repository.lastUsedInventoryId, 'a');
    expect(usedType, ShopItemEntity.effectTimeFreeze);
    expect(usedEffects?['seconds'], 10);
  });

  testWidgets('tapping does not invoke onUse when the repository fails', (
    tester,
  ) async {
    final provider = GamificationProvider(
      repository: _FakeRepository(
        items: [
          _powerUpItem(
            id: 'a',
            itemType: ShopItemEntity.effectTimeFreeze,
            quantity: 1,
          ),
        ],
        useItemEffects: null,
      ),
    );
    await provider.loadInventory();

    var called = false;

    await tester.pumpWidget(
      _wrap(
        provider,
        GamePowerUpTray(
          availableTypes: const [ShopItemEntity.effectTimeFreeze],
          onUse: (_, __) => called = true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });

  testWidgets('disables tapping when enabled is false', (tester) async {
    final repository = _FakeRepository(
      items: [
        _powerUpItem(
          id: 'a',
          itemType: ShopItemEntity.effectTimeFreeze,
          quantity: 1,
        ),
      ],
      useItemEffects: {'seconds': 10},
    );
    final provider = GamificationProvider(repository: repository);
    await provider.loadInventory();

    await tester.pumpWidget(
      _wrap(
        provider,
        GamePowerUpTray(
          availableTypes: const [ShopItemEntity.effectTimeFreeze],
          onUse: (_, __) {},
          enabled: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(repository.lastUsedInventoryId, isNull);
  });
}
