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
import 'package:lexilingo_app/features/gamification/presentation/widgets/shop_item_card.dart';
import 'package:provider/provider.dart';

class _Repo implements GamificationRepository {
  int walletCalls = 0;
  int purchases = 0;

  @override
  Future<WalletEntity> getWallet() async {
    walletCalls++;
    throw Exception('offline');
  }

  @override
  Future<List<ShopItemEntity>> getShopItems() async => [
    ShopItemEntity.fromJson({
      'id': 'i',
      'name': 'Heart',
      'description': 'd',
      'category': 'power_ups',
      'price_gems': 10,
      'effect_type': 'heart_refill',
    }),
  ];

  @override
  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async {
    purchases++;
    return true;
  }

  @override
  Future<List<InventoryItemEntity>> getInventory() async => [];
  @override
  Future<List<WalletTransactionEntity>> getTransactions({
    int limit = 50,
  }) async => [];
  @override
  Future<StarterRewardEntity?> getPendingStarterReward() async => null;
  @override
  Future<bool> acknowledgeStarterReward() async => false;
  @override
  Future<Map<String, dynamic>?> useItem(
    String inventoryId, {
    String? gameSessionId,
  }) async => null;
  @override
  Future<String?> equipAvatar(String inventoryId) async => null;
  @override
  Future<LeaderboardEntity> getLeaderboard(String league) async =>
      throw UnimplementedError();
  @override
  Future<LeagueStatusEntity> getLeagueStatus() async =>
      throw UnimplementedError();
}

void main() {
  testWidgets('a failed wallet load shows a retry and blocks the purchase', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
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
    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.walletUnavailable, isTrue);

    // The failure is visible (with a retry) and the buy button is inert.
    expect(find.text('errors.somethingWrong'), findsOneWidget);
    expect(find.byTooltip('common.retry'), findsOneWidget);
    final card = find.byType(ShopItemCard);
    expect(card, findsOneWidget);
    await tester.tap(
      find.descendant(of: card, matching: find.byType(GestureDetector)).last,
    );
    await tester.pump();

    expect(find.text('shop.notEnoughGems'), findsNothing);
    expect(repo.purchases, 0);

    final before = repo.walletCalls;
    await tester.tap(find.byTooltip('common.retry'));
    await tester.pump();
    expect(repo.walletCalls, before + 1);
  });
}
