import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/gem_counter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo implements GamificationRepository {
  final List<Completer<WalletEntity>> wallets = [];
  final shop = Completer<List<ShopItemEntity>>();
  final inventory = Completer<List<InventoryItemEntity>>();
  final board = Completer<LeaderboardEntity>();
  final starter = Completer<StarterRewardEntity?>();

  @override
  Future<WalletEntity> getWallet() {
    final c = Completer<WalletEntity>();
    wallets.add(c);
    return c.future;
  }

  @override
  Future<List<InventoryItemEntity>> getInventory() => inventory.future;
  @override
  Future<List<WalletTransactionEntity>> getTransactions({
    int limit = 50,
  }) async => [];
  @override
  Future<StarterRewardEntity?> getPendingStarterReward() => starter.future;
  @override
  Future<bool> acknowledgeStarterReward() async => false;
  @override
  Future<List<ShopItemEntity>> getShopItems() => shop.future;
  @override
  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async => false;
  @override
  Future<Map<String, dynamic>?> useItem(
    String inventoryId, {
    String? gameSessionId,
  }) async => null;
  @override
  Future<String?> equipAvatar(String inventoryId) async => null;
  @override
  Future<LeaderboardEntity> getLeaderboard(String league) => board.future;
  @override
  Future<LeagueStatusEntity> getLeagueStatus() async =>
      throw UnimplementedError();
}

WalletEntity _wallet(int gems) =>
    WalletEntity(id: 'w', userId: 'u', gems: gems);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an older wallet response arriving last is ignored', () async {
    final repo = _Repo();
    final provider = GamificationProvider(repository: repo);

    final first = provider.loadWallet();
    final second = provider.loadWallet();
    repo.wallets[1].complete(_wallet(10));
    await second;
    repo.wallets[0].complete(_wallet(65));
    await first;

    expect(provider.wallet?.gems, 10);
    expect(provider.isLoadingWallet, isFalse);
  });

  test('a failed reload keeps the last known balance', () async {
    final repo = _Repo();
    final provider = GamificationProvider(repository: repo);
    final ok = provider.loadWallet();
    repo.wallets[0].complete(_wallet(7));
    await ok;

    final bad = provider.loadWallet();
    repo.wallets[1].completeError(Exception('offline'));
    await bad;

    expect(provider.wallet?.gems, 7);
    expect(provider.walletError, isNotNull);
  });

  test('reset forgets the wallet and a response in flight', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo();
    final provider = GamificationProvider(repository: repo);
    final done = provider.loadWallet();
    repo.wallets[0].complete(_wallet(65));
    await done;

    final inFlight = provider.loadWallet();
    provider.reset();
    repo.wallets[1].complete(_wallet(99));
    await inFlight;
    await Future<void>.delayed(Duration.zero);

    expect(provider.wallet, isNull);
    expect(provider.gems, 0);
    expect(provider.isLoadingWallet, isFalse);
    expect(provider.selectedLeague, 'bronze');
  });

  testWidgets('the gem pill shows a dash until the wallet is known', (
    tester,
  ) async {
    final repo = _Repo();
    final provider = GamificationProvider(repository: repo);

    Widget pill() => MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: provider,
          builder: (_, __) => GemCounter(gems: provider.wallet?.gems),
        ),
      ),
    );

    await tester.pumpWidget(pill());
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    final load = provider.loadWallet();
    repo.wallets[0].complete(_wallet(42));
    await load;
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  test('no loader writes a response that lands after reset()', () async {
    final repo = _Repo();
    final provider = GamificationProvider(
      repository: repo,
      enableStarterReward: true,
    );

    final loads = Future.wait([
      provider.loadShopItems(),
      provider.loadInventory(),
      provider.loadLeaderboard(),
      provider.loadPendingStarterReward(),
    ]);
    provider.reset();
    repo.shop.complete([]);
    repo.inventory.complete([]);
    repo.board.complete(
      LeaderboardEntity(
        league: 'bronze',
        weekStart: DateTime(2026, 1, 5),
        weekEnd: DateTime(2026, 1, 11),
        entries: const [],
      ),
    );
    repo.starter.complete(null);
    await loads;

    expect(provider.leaderboard, isNull);
    expect(provider.isLoadingShop, isFalse);
    expect(provider.isLoadingInventory, isFalse);
    expect(provider.isLoadingLeaderboard, isFalse);
    expect(provider.isLoadingStarterReward, isFalse);
  });

  test('a failed first wallet load is reported, not shown as 0', () async {
    final repo = _Repo();
    final provider = GamificationProvider(repository: repo);
    final load = provider.loadWallet();
    repo.wallets[0].completeError(Exception('offline'));
    await load;

    expect(provider.wallet, isNull);
    expect(provider.walletUnavailable, isTrue);

    final retry = provider.loadWallet();
    repo.wallets[1].complete(_wallet(5));
    await retry;
    expect(provider.walletUnavailable, isFalse);
  });

  testWidgets('the placeholder is labelled for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GemCounter(gems: null, failed: true)),
      ),
    );
    expect(
      tester.getSemantics(find.byType(GemCounter)).label,
      contains('errors.loadFailed'),
    );
    semantics.dispose();
  });
}
