import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/core/permissions/admin_permissions.dart';
import 'package:lexilingo_app/features/admin/features/gamification/data/gamification_repository.dart';
import 'package:lexilingo_app/features/admin/features/gamification/presentation/achievements_shop_screen.dart';
import 'package:provider/provider.dart';

class _FakeRepo extends GamificationRepository {
  _FakeRepo({this.achievements = const [], this.shop = const [], this.error});
  final List<AchievementItem> achievements;
  final List<ShopItem> shop;
  final Object? error;
  final hidden = <String, bool>{};
  final available = <String, bool>{};

  @override
  Future<List<AchievementItem>> listAchievements() async {
    if (error != null) throw error!;
    return achievements;
  }

  @override
  Future<List<ShopItem>> listShop() async => shop;

  @override
  Future<void> setHidden(String id, bool h) async => hidden[id] = h;

  @override
  Future<void> setAvailable(String id, bool a) async => available[id] = a;
}

AchievementItem _ach() => const AchievementItem(
  id: 'a1',
  name: 'First steps',
  description: 'Finish a lesson',
  category: 'lessons',
  rarity: 'common',
  conditionType: 'lesson_complete',
  conditionValue: 1,
  xpReward: 10,
  gemsReward: 5,
  isHidden: false,
);

ShopItem _item() => const ShopItem(
  id: 's1',
  name: 'Streak freeze',
  description: 'Keep the streak',
  itemType: 'streak_freeze',
  priceGems: 50,
  isAvailable: true,
);

Future<void> _pump(
  WidgetTester tester,
  GamificationRepository repo, {
  List<String> perms = const [
    'achievements:update',
    'shop:update',
    'achievements:create',
  ],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final p = AdminPermissions()..apply({'all': false, 'permissions': perms});
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(home: AchievementsShopScreen(repository: repo)),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('models read the API fields', () {
    final a = AchievementItem.fromJson({
      'id': 1,
      'name': 'N',
      'condition_value': 3,
      'xp_reward': 20,
      'is_hidden': true,
    });
    expect(a.id, '1');
    expect(a.conditionValue, 3);
    expect(a.isHidden, isTrue);
    final s = ShopItem.fromJson({
      'id': 2,
      'name': 'S',
      'price_gems': 40,
      'stock_quantity': 7,
      'is_available': true,
      'effects': {'x': 1},
    });
    expect(s.stock, 7);
    expect(s.effects['x'], 1);
    expect(ShopItem.fromJson({'id': 3}).stock, isNull);
  });

  testWidgets('hide switch calls the repository', (tester) async {
    final repo = _FakeRepo(achievements: [_ach()], shop: [_item()]);
    await _pump(tester, repo);
    expect(find.text('First steps'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(repo.hidden['a1'], isTrue);
  });

  testWidgets('shop tab lists items and toggles availability', (tester) async {
    final repo = _FakeRepo(achievements: [_ach()], shop: [_item()]);
    await _pump(tester, repo);
    await tester.tap(find.text('adminGrowth.gamify.tabShop'));
    await tester.pumpAndSettle();
    expect(find.text('Streak freeze'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(repo.available['s1'], isFalse);
  });

  testWidgets('no delete control and read-only role cannot toggle', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepo(achievements: [_ach()]),
      perms: ['achievements:read'],
    );
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    expect(find.text('adminGrowth.gamify.new'), findsNothing);
  });

  testWidgets('empty achievements shows the empty state', (tester) async {
    await _pump(tester, _FakeRepo());
    expect(find.text('adminGrowth.gamify.emptyAchievements'), findsOneWidget);
  });

  testWidgets('failure shows an error body', (tester) async {
    await _pump(tester, _FakeRepo(error: Exception('boom')));
    expect(find.text('First steps'), findsNothing);
    expect(find.byType(CustomScrollView), findsNothing);
  });
}
