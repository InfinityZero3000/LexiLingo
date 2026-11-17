import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/gem_counter.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/shop_item_card.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/presentation/screens/wallet_screen.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/boost_purchase_animation.dart';

/// Shop Screen
/// Browse and purchase items with gems
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _purchasingItemId;

  final List<_CategoryTab> _categories = [
    _CategoryTab('all', 'shop.categoryAll', Icons.apps),
    _CategoryTab(
      ShopItemEntity.categoryPowerUps,
      'shop.categoryPowerUps',
      Icons.bolt,
    ),
    _CategoryTab(
      ShopItemEntity.categoryBoosts,
      'shop.categoryBoosts',
      Icons.rocket_launch,
    ),
    _CategoryTab(
      ShopItemEntity.categoryCosmetics,
      'shop.categoryCosmetics',
      Icons.palette,
    ),
    _CategoryTab(
      ShopItemEntity.categorySpecial,
      'shop.categorySpecial',
      Icons.star,
    ),
  ];

  @override
  void initState() {
    super.initState();
    final selected = context.read<GamificationProvider>().selectedCategory;
    final initialIndex = _categories.indexWhere((c) => c.id == selected);
    _tabController = TabController(
      length: _categories.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    );
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<GamificationProvider>();
      provider.loadShopItems();
      provider.loadWallet();
      provider.loadInventory();
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final category = _categories[_tabController.index].id;
    context.read<GamificationProvider>().setCategory(category);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handlePurchase(ShopItemEntity item) async {
    if (_purchasingItemId != null) return;
    final provider = context.read<GamificationProvider>();

    // Check if can afford
    if (provider.gems < item.priceGems) {
      _showNotEnoughGemsDialog();
      return;
    }

    // Confirm purchase
    final confirmed = await _showPurchaseConfirmation(item);
    if (!mounted || !confirmed) return;

    setState(() => _purchasingItemId = item.id);

    final success = await provider.purchaseItem(item.id);

    if (!mounted) return;
    setState(() => _purchasingItemId = null);

    if (success) {
      if (item.category == ShopItemEntity.categoryBoosts) {
        await BoostPurchaseAnimation.show(
          context,
          item: item,
          onComplete: () {},
        );
        if (!mounted) return;
      }
      _showPurchaseSuccess(item);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('shop.purchaseFailed'.tr()),
          backgroundColor: AppColors.errorBright,
        ),
      );
    }
  }

  Future<bool> _showPurchaseConfirmation(ShopItemEntity item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            title: Text('shop.confirmPurchase'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.purple,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: item.isAvatar
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                child: NetworkAvatarImage(
                                  imageUrl: item.avatarUrl,
                                ),
                              )
                            : Icon(
                                Icons.card_giftcard,
                                color: AppColors.surfaceLight,
                              ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(
                                  Icons.diamond,
                                  size: 16,
                                  color: AppColors.purple,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  '${item.priceGems}',
                                  style: const TextStyle(
                                    color: AppColors.purple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'shop.confirmPurchaseQuestion'.tr(),
                  style: TextStyle(color: AppColorRoles.textMuted(isDark)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('common.cancel'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                  backgroundColor: AppColors.greenSuccessBright,
                  foregroundColor: AppColors.surfaceLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: Text('shop.purchase'.tr()),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showPurchaseSuccess(ShopItemEntity item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.greenSuccessBright.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.greenSuccessBright,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'shop.purchaseSuccessful'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'shop.addedToInventory'.tr(namedArgs: {'name': item.name}),
              style: TextStyle(color: AppColorRoles.textMuted(isDark)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('shop.great'.tr()),
          ),
          if (item.isAvatar)
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(this.context);
                final avatarUrl = await this.context
                    .read<GamificationProvider>()
                    .equipAvatar(item.id);
                if (!mounted) return;
                if (avatarUrl != null) {
                  await this.context.read<AuthProvider>().refreshCurrentUser();
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('shop.avatarEquipped'.tr())),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('shop.avatarEquipFailed'.tr()),
                      backgroundColor: AppColors.errorBright,
                    ),
                  );
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                backgroundColor: primaryColor,
                foregroundColor: AppColors.surfaceLight,
              ),
              child: Text('shop.equipNow'.tr()),
            ),
        ],
      ),
    );
  }

  void _showNotEnoughGemsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.diamond_outlined,
                color: AppColors.orange,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'shop.notEnoughGems'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'shop.earnMoreGems'.tr(),
              style: TextStyle(color: AppColorRoles.textMuted(isDark)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Center(
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                backgroundColor: primaryColor,
                foregroundColor: AppColors.surfaceLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: Text('shop.gotIt'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Scaffold(
      appBar: AppBar(
        title: Text('shop.title'.tr()),
        centerTitle: true,
        actions: [
          Consumer<GamificationProvider>(
            builder: (context, provider, child) {
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: GemCounter(
                  gems: provider.gems,
                  onTap: () {
                    // Navigate to wallet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WalletScreen(),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: primaryColor,
          unselectedLabelColor: AppColors.textGrey,
          indicatorColor: primaryColor,
          tabs: _categories.map((cat) {
            return Tab(
              child: Row(
                children: [
                  Icon(cat.icon, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(cat.label.tr()),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      body: ContentWidth(
        child: Consumer<GamificationProvider>(
          builder: (context, provider, child) {
            if (provider.isLoadingShop && provider.shopItems.isEmpty) {
              return const Center(child: LottieLoadingWidget.medium());
            }

            if (provider.shopError != null && provider.shopItems.isEmpty) {
              return ErrorDisplayWidget.fromMessage(
                message: provider.shopError!,
                onRetry: () => provider.loadShopItems(),
              );
            }

            final items = provider.filteredShopItems;

            if (items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 64,
                      color: AppColors.grey400,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'shop.noItemsInCategory'.tr(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColorRoles.textMuted(isDark),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                await provider.loadShopItems();
                await provider.loadWallet();
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.68,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ShopItemCard(
                    item: item,
                    userGems: provider.gems,
                    isOwned: item.isAvatar && provider.ownsItem(item.id),
                    isLoading: _purchasingItemId == item.id,
                    onPurchase: () => _handlePurchase(item),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryTab {
  final String id;
  final String label;
  final IconData icon;

  _CategoryTab(this.id, this.label, this.icon);
}
