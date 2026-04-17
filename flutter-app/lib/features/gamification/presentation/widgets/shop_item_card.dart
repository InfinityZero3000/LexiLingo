import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

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
          color: _getCategoryColor(context, item.category).withValues(alpha: 0.2),
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
                    _getCategoryColor(context, item.category).withValues(alpha: 0.15),
                    _getCategoryColor(context, item.category).withValues(alpha: 0.05),
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
                  Center(child: _buildItemIcon(context)),

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
                              : AppColors.orange.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.isOutOfStock
                              ? 'SOLD OUT'
                              : '${item.stockRemaining} LEFT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.surface,
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
                          color: AppColorRoles.primary(
                            Theme.of(context).brightness == Brightness.dark,
                          ).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer,
                              size: 12,
                              color: AppColors.surfaceLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${item.effectDuration}h',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.surfaceLight,
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
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
                          color: AppColors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.diamond,
                              size: 14,
                              color: AppColors.purple,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${item.priceGems}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.purple,
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
                                ? AppColors.greenSuccessBright
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: isLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: LottieLoadingWidget.tiny(),
                                )
                              : Text(
                                  item.isOutOfStock ? 'SOLD' : 'BUY',
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

  Widget _buildItemIcon(BuildContext context) {
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
            _getCategoryColor(context, item.category),
            _getCategoryColor(context, item.category).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _getCategoryColor(context, item.category).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: AppColors.surfaceLight, size: 32),
    );
  }

  Color _getCategoryColor(BuildContext context, String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (category) {
      case ShopItemEntity.categoryPowerUps:
        return AppColorRoles.primary(isDark);
      case ShopItemEntity.categoryCosmetics:
        return const Color(0xFFEC4899); // Pink
      case ShopItemEntity.categoryBoosts:
        return AppColors.orange; // Amber
      case ShopItemEntity.categorySpecial:
        return AppColors.purple; // Purple
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }
}
