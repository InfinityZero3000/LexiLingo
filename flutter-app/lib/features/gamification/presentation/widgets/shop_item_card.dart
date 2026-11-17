import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/gamification/presentation/theme/reward_palette.dart';
import 'package:lexilingo_app/core/widgets/game_icon.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';

/// Shop Item Card Widget
/// Displays a purchasable item in the shop
class ShopItemCard extends StatelessWidget {
  final ShopItemEntity item;
  final int userGems;
  final VoidCallback? onPurchase;
  final bool isLoading;
  final bool isOwned;

  const ShopItemCard({
    super.key,
    required this.item,
    required this.userGems,
    this.onPurchase,
    this.isLoading = false,
    this.isOwned = false,
  });

  bool get canAfford => userGems >= item.priceGems;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: _getCategoryColor(
            context,
            item.category,
          ).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
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
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getCategoryColor(
                      context,
                      item.category,
                    ).withValues(alpha: 0.15),
                    _getCategoryColor(
                      context,
                      item.category,
                    ).withValues(alpha: 0.05),
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
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: item.isOutOfStock
                              ? AppColors.errorBright.withValues(alpha: 0.9)
                              : AppColors.orange.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          item.isOutOfStock
                              ? 'shop.soldOut'.tr()
                              : 'shop.stockLeft'.tr(
                                  namedArgs: {
                                    'count': '${item.stockRemaining}',
                                  },
                                ),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.surfaceLight,
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
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColorRoles.primary(
                            Theme.of(context).brightness == Brightness.dark,
                          ).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer,
                              size: 12,
                              color: AppColors.surfaceLight,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '${item.effectDuration}h',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
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

          // Item Info: sized by its content so the icon area absorbs the slack
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.description,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.grey600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),

                // Price and Buy Button
                Row(
                  children: [
                    // Price
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.diamond,
                              size: 14,
                              color: AppColors.purple,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                '${item.priceGems}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.purple,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),

                    // Buy Button
                    GestureDetector(
                      onTap:
                          canAfford &&
                              !item.isOutOfStock &&
                              !isLoading &&
                              !isOwned
                          ? onPurchase
                          : null,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: canAfford && !item.isOutOfStock && !isOwned
                              ? AppColors.greenSuccessBright
                              : AppColors.grey300,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: isLoading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: LottieLoadingWidget.tiny(),
                              )
                            : Text(
                                isOwned
                                    ? 'OWNED'
                                    : item.isOutOfStock
                                    ? 'SOLD'
                                    : 'BUY',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          canAfford &&
                                              !item.isOutOfStock &&
                                              !isOwned
                                          ? AppColors.surfaceLight
                                          : AppColors.grey600,
                                    ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemIcon(BuildContext context) {
    if (item.isAvatar && item.avatarUrl != null) {
      return Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _getCategoryColor(
            context,
            item.category,
          ).withValues(alpha: 0.1),
          border: Border.all(
            color: _getCategoryColor(context, item.category),
            width: 2,
          ),
        ),
        child: ClipOval(
          child: NetworkAvatarImage(
            imageUrl: item.avatarUrl,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    final gameIcon = gamePowerUpIcons[item.effectType];

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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: _getCategoryColor(
              context,
              item.category,
            ).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: gameIcon != null
            ? AppGameIcon(
                gameIcon,
                size: 32,
                fallbackColor: AppColors.surfaceLight,
              )
            : Icon(icon, color: AppColors.surfaceLight, size: 32),
      ),
    );
  }

  Color _getCategoryColor(BuildContext context, String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (category) {
      case ShopItemEntity.categoryPowerUps:
        return AppColorRoles.primary(isDark);
      case ShopItemEntity.categoryCosmetics:
        return RewardPalette.shopPink;
      case ShopItemEntity.categoryBoosts:
        return AppColors.orange; // Amber
      case ShopItemEntity.categorySpecial:
        return AppColors.purple; // Purple
      default:
        return AppColors.grey500;
    }
  }
}
