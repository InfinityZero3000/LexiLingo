import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';

/// Shop Item Card Widget
/// Displays a purchasable item in the shop
class ShopItemCard extends StatelessWidget {
  final ShopItemEntity item;
  final int userGems;
  final VoidCallback? onPurchase;
  final bool isLoading;

  const ShopItemCard({
    super.key,
    required this.item,
    required this.userGems,
    this.onPurchase,
    this.isLoading = false,
  });

  bool get canAfford => userGems >= item.priceGems;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getCategoryColor(item.category).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Item Icon/Image
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getCategoryColor(item.category).withValues(alpha: 0.15),
                    _getCategoryColor(item.category).withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Stack(
                children: [
                  // Item Icon
                  Center(
                    child: _buildItemIcon(),
                  ),
                  
                  // Limited stock badge
                  if (item.isLimitedStock)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: item.isOutOfStock
                              ? Colors.red.withValues(alpha: 0.9)
                              : Colors.orange.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.isOutOfStock
                              ? 'SOLD OUT'
                              : '${item.stockRemaining} LEFT',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    
                  // Effect duration badge
                  if (item.effectDuration != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${item.effectDuration}h',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Item Info
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Price and Buy Button
                  Row(
                    children: [
                      // Price
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.diamond,
                              size: 14,
                              color: Color(0xFF8B5CF6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${item.priceGems}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8B5CF6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      
                      // Buy Button
                      GestureDetector(
                        onTap: canAfford && !item.isOutOfStock && !isLoading
                            ? onPurchase
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: canAfford && !item.isOutOfStock
                                ? const Color(0xFF10B981)
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  item.isOutOfStock
                                      ? 'SOLD'
                                      : 'BUY',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: canAfford && !item.isOutOfStock
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemIcon() {
    IconData icon;
    switch (item.effectType) {
      case ShopItemEntity.effectStreakFreeze:
        icon = Icons.ac_unit;
        break;
      case ShopItemEntity.effectDoubleXP:
        icon = Icons.auto_awesome;
        break;
      case ShopItemEntity.effectUnlimitedHearts:
        icon = Icons.favorite;
        break;
      case ShopItemEntity.effectHintRefill:
        icon = Icons.lightbulb;
        break;
      default:
        icon = Icons.card_giftcard;
    }

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getCategoryColor(item.category),
            _getCategoryColor(item.category).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _getCategoryColor(item.category).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 32,
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case ShopItemEntity.categoryPowerUps:
        return const Color(0xFF3B82F6); // Blue
      case ShopItemEntity.categoryCosmetics:
        return const Color(0xFFEC4899); // Pink
      case ShopItemEntity.categoryBoosts:
        return const Color(0xFFF59E0B); // Amber
      case ShopItemEntity.categorySpecial:
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }
}
