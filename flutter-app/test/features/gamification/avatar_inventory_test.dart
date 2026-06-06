import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';

void main() {
  test('inventory retains permanent avatar metadata', () {
    const url = 'https://api.dicebear.com/7.x/adventurer/svg?seed=Cosmo';
    final inventory = InventoryItemEntity.fromJson({
      'id': 'inventory-1',
      'quantity': 1,
      'purchased_at': '2026-06-06T00:00:00Z',
      'item': {
        'id': 'avatar-1',
        'name': 'Cosmo Avatar',
        'description': 'Avatar',
        'item_type': 'avatar',
        'price_gems': 20,
        'icon_url': url,
        'effects': {'avatar_url': url},
      },
    });

    expect(inventory.item.isAvatar, isTrue);
    expect(inventory.item.avatarUrl, url);
    expect(inventory.quantity, 1);
  });
}
