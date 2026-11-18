import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/screens/shop_screen.dart';
import 'package:provider/provider.dart';

class _Repo implements GamificationRepository {
  _Repo(this.items);
  List<InventoryItemEntity> items;
  int inventoryCalls = 0;

  @override
  Future<List<InventoryItemEntity>> getInventory() async {
    inventoryCalls++;
    return items;
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
  Future<Map<String, dynamic>?> useItem(String inventoryId) async => null;
  @override
  Future<String?> equipAvatar(String inventoryId) async => null;
  @override
  Future<LeaderboardEntity> getLeaderboard(String league) async =>
      throw UnimplementedError();
  @override
  Future<LeagueStatusEntity> getLeagueStatus() async =>
      throw UnimplementedError();
}

InventoryItemEntity _boost(DateTime expiresAt) => InventoryItemEntity.fromJson({
  'id': 'inv',
  'item': {
    'id': 'item',
    'name': 'Double XP',
    'description': 'd',
    'category': 'boosts',
    'price_gems': 50,
    'icon_url': '',
    'effect_type': 'double_xp',
    'effect_duration': 24,
    'effects': {},
    'is_available': true,
  },
  'quantity': 1,
  'is_active': true,
  'expires_at': expiresAt.toUtc().toIso8601String(),
  'activated_at': DateTime.now().toUtc().toIso8601String(),
  'purchased_at': DateTime.now().toUtc().toIso8601String(),
});

Future<void> _pumpShop(WidgetTester tester, _Repo repo, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = GamificationProvider(repository: repo);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: ShopScreen()),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('shop shows the active boost bar with remaining time at 375px', (
    tester,
  ) async {
    final repo = _Repo([_boost(DateTime.now().add(const Duration(hours: 2)))]);
    await _pumpShop(tester, repo, 375);
    expect(find.text('2× XP'), findsOneWidget);
    expect(find.textContaining('1h'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shop reserves no space for the bar without active boosts', (
    tester,
  ) async {
    await _pumpShop(tester, _Repo([]), 375);
    expect(find.text('2× XP'), findsNothing);
    expect(find.byType(TabBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
