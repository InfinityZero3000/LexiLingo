import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';

void main() {
  test('maps backend boost fields and duration', () {
    final item = ShopItemEntity.fromJson({
      'id': 'boost-1',
      'name': 'Double XP',
      'description': 'Boost',
      'item_type': 'double_xp',
      'price_gems': 25,
      'effects': {'duration_hours': 2, 'multiplier': 2},
    });

    expect(item.category, ShopItemEntity.categoryBoosts);
    expect(item.effectType, ShopItemEntity.effectDoubleXP);
    expect(item.effectDuration, 2);
  });

  test('maps avatar as cosmetic and exposes its image URL', () {
    const url = 'https://api.dicebear.com/7.x/adventurer/svg?seed=Sunny';
    final item = ShopItemEntity.fromJson({
      'id': 'avatar-1',
      'name': 'Sunny Avatar',
      'description': 'Avatar',
      'item_type': 'avatar',
      'price_gems': 10,
      'icon_url': url,
      'effects': {'avatar_url': url},
    });

    expect(item.category, ShopItemEntity.categoryCosmetics);
    expect(item.isAvatar, isTrue);
    expect(item.avatarUrl, url);
  });

  test('maps consumables into power ups', () {
    for (final type in ['streak_freeze', 'hint_pack', 'heart_refill']) {
      final item = ShopItemEntity.fromJson({
        'id': type,
        'name': type,
        'description': type,
        'item_type': type,
        'price_gems': 15,
      });
      expect(item.category, ShopItemEntity.categoryPowerUps);
    }
  });

  test('maps all in-game power-up item types into power ups category', () {
    for (final type in ShopItemEntity.gamePowerUpEffectTypes) {
      final item = ShopItemEntity.fromJson({
        'id': type,
        'name': type,
        'description': type,
        'item_type': type,
        'price_gems': 15,
      });
      expect(
        item.category,
        ShopItemEntity.categoryPowerUps,
        reason: '$type should map to categoryPowerUps',
      );
      expect(item.effectType, type);
    }
  });
}
