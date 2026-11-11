import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/presentation/widgets/achievement_widgets.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_card.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/shop_item_card.dart';

Future<void> _pumpCell(WidgetTester tester, Size cell, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: cell.width, height: cell.height, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

// Only vertical overflow is asserted: the test font (Ahem) is wider than the
// real one and untranslated keys are long, so a horizontal overflow here is
// not evidence of one on a device.
void _expectNoBottomOverflow(WidgetTester tester) {
  final e = tester.takeException();
  expect(e?.toString() ?? '', isNot(contains('bottom')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Cell = (screen - padding - gaps) / columns, height = width / aspect ratio.
  Size cell(double screen, int cols, double pad, double gap, double ratio) {
    final w = (screen - pad * 2 - gap * (cols - 1)) / cols;
    return Size(w, w / ratio);
  }

  for (final screen in [320.0, 360.0, 393.0]) {
    testWidgets('ShopItemCard fits its grid cell at $screen', (tester) async {
      const item = ShopItemEntity(
        id: '1',
        name: 'Magnifying Glass',
        description: 'Reveals a hint during a game round for a short while',
        category: ShopItemEntity.categoryPowerUps,
        priceGems: 10,
        iconUrl: '',
        effectType: ShopItemEntity.effectRevealHint,
        effectDuration: 24,
        stockLimit: 5,
        stockRemaining: 3,
      );
      await _pumpCell(
        tester,
        cell(screen, 2, 16, 12, 0.68),
        const ShopItemCard(item: item, userGems: 100),
      );
      _expectNoBottomOverflow(tester);
    });

    testWidgets('AchievementCard fits its grid cell at $screen', (
      tester,
    ) async {
      const a = AchievementEntity(
        id: '1',
        name: 'Seven Day Streak Master',
        description: 'Practice seven days in a row',
        conditionType: 'streak',
        conditionValue: 7,
        category: 'streak',
        xpReward: 100,
        gemsReward: 10,
        rarity: 'legendary',
      );
      await _pumpCell(
        tester,
        cell(screen, 3, 12, 8, 0.75),
        const AchievementCard(achievement: a, isUnlocked: true),
      );
      _expectNoBottomOverflow(tester);
    });

    for (final type in GameType.values) {
      testWidgets('GameCard ${type.name} fits its grid cell at $screen', (
        tester,
      ) async {
        await _pumpCell(
          tester,
          cell(screen, 2, 16, 12, 0.85),
          GameCard(gameType: type, bestScore: 1200),
        );
        _expectNoBottomOverflow(tester);
      });
    }
  }
}
