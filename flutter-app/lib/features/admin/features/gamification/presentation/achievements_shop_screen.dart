import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/empty_state_widget.dart';
import 'package:lexilingo_app/core/widgets/filter_chip_bar.dart';
import 'package:provider/provider.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/growth_form.dart';
import '../../../shared/widgets/growth_state_body.dart';
import '../data/gamification_repository.dart';
import 'achievement_form.dart';
import 'shop_form.dart';

class AchievementsShopScreen extends StatefulWidget {
  const AchievementsShopScreen({super.key, this.repository});

  final GamificationRepository? repository;

  @override
  State<AchievementsShopScreen> createState() => _AchievementsShopScreenState();
}

class _AchievementsShopScreenState extends State<AchievementsShopScreen> {
  late final GamificationRepository _repo =
      widget.repository ?? GamificationRepository();
  List<AchievementItem> _achievements = const [];
  List<ShopItem> _shop = const [];
  bool _loading = true;
  Object? _error;
  String? _category;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.listAchievements(),
        _repo.listShop(),
      ]);
      if (!mounted) return;
      setState(() {
        _achievements = results[0] as List<AchievementItem>;
        _shop = results[1] as List<ShopItem>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      final api = AdminApiError.from(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            api.isForbidden
                ? api.message.resolve()
                : 'adminGrowth.common.actionFailed'.tr(),
          ),
        ),
      );
    }
  }

  Future<void> _openAchievementForm([AchievementItem? item]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AchievementForm(item: item, repository: _repo),
    );
    if (saved == true) await _load();
  }

  Future<void> _openShopForm([ShopItem? item]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ShopForm(item: item, repository: _repo),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final perms = context.watch<AdminPermissions>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            icon: const Icon(Icons.menu_rounded),
            onPressed: AdminShell.openDrawer,
          ),
          title: Text('adminGrowth.gamify.title'.tr()),
          actions: [
            IconButton(
              onPressed: _load,
              tooltip: 'adminGrowth.common.refresh'.tr(),
              icon: const Icon(Icons.refresh_outlined),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'adminGrowth.gamify.tabAchievements'.tr()),
              Tab(text: 'adminGrowth.gamify.tabShop'.tr()),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tab(
              hasData: _achievements.isNotEmpty,
              child: _achievementsList(perms),
            ),
            _tab(hasData: _shop.isNotEmpty, child: _shopList(perms)),
          ],
        ),
      ),
    );
  }

  Widget _tab({required bool hasData, required Widget child}) =>
      RefreshIndicator(
        onRefresh: _load,
        child: GrowthStateBody(
          isLoading: _loading,
          hasData: hasData || (!_loading && _error == null),
          error: _error,
          onRetry: _load,
          builder: (_) => child,
        ),
      );

  Widget _achievementsList(AdminPermissions perms) {
    final items = _category == null
        ? _achievements
        : _achievements.where((a) => a.category == _category).toList();
    final canCreate = perms.can('achievements:create');
    final canUpdate = perms.can('achievements:update');
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilterChipBar<String>(
                  allowClear: true,
                  selected: _category,
                  onSelected: (v) => setState(() => _category = v),
                  options: [
                    for (final c in achievementCategories)
                      FilterOption(value: c, label: c),
                  ],
                ),
                if (canCreate)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                        ),
                        onPressed: () => _openAchievementForm(),
                        icon: const Icon(Icons.add),
                        label: Text('adminGrowth.gamify.new'.tr()),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              icon: Icons.military_tech_outlined,
              title: 'adminGrowth.gamify.emptyAchievements'.tr(),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) => AchievementCard(
                item: items[i],
                onTap: canUpdate ? () => _openAchievementForm(items[i]) : null,
                onToggle: canUpdate
                    ? () => _write(
                        () => _repo.setHidden(items[i].id, !items[i].isHidden),
                      )
                    : null,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: GrowthWebOnlyNote()),
      ],
    );
  }

  Widget _shopList(AdminPermissions perms) {
    final canCreate = perms.can('shop:create');
    final canUpdate = perms.can('shop:update');
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'adminGrowth.gamify.inventoryCount'.tr(
                      args: ['${_shop.length}'],
                    ),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (canCreate)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                    ),
                    onPressed: () => _openShopForm(),
                    icon: const Icon(Icons.add),
                    label: Text('adminGrowth.gamify.newItem'.tr()),
                  ),
              ],
            ),
          ),
        ),
        if (_shop.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              icon: Icons.storefront_outlined,
              title: 'adminGrowth.gamify.emptyShop'.tr(),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            sliver: SliverList.separated(
              itemCount: _shop.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) => ShopCard(
                item: _shop[i],
                onTap: canUpdate ? () => _openShopForm(_shop[i]) : null,
                onToggle: canUpdate
                    ? () => _write(
                        () => _repo.setAvailable(
                          _shop[i].id,
                          !_shop[i].isAvailable,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: GrowthWebOnlyNote()),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}

class _RemoteIcon extends StatelessWidget {
  const _RemoteIcon({required this.url, required this.fallback});
  final String url;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(fallback, color: scheme.primary);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: AppRadius.mdAll,
      ),
      child: url.startsWith('http')
          ? Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => icon,
            )
          : icon,
    );
  }
}

class AchievementCard extends StatelessWidget {
  const AchievementCard({
    super.key,
    required this.item,
    this.onTap,
    this.onToggle,
  });

  final AchievementItem item;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardShell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RemoteIcon(url: item.badgeIcon, fallback: Icons.military_tech),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xs + 2,
                  children: [
                    GrowthChip(item.category.isEmpty ? '—' : item.category),
                    GrowthChip(item.rarity),
                    GrowthChip(
                      '${item.conditionType} ≥ ${item.conditionValue}',
                    ),
                    GrowthChip(
                      'adminGrowth.gamify.rewardChip'.tr(
                        args: ['${item.xpReward}', '${item.gemsReward}'],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Semantics(
            label: item.isHidden
                ? 'adminGrowth.gamify.hidden'.tr()
                : 'adminGrowth.common.active'.tr(),
            child: Switch(
              value: !item.isHidden,
              onChanged: onToggle == null ? null : (_) => onToggle!(),
            ),
          ),
        ],
      ),
    );
  }
}

class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.item, this.onTap, this.onToggle});

  final ShopItem item;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardShell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RemoteIcon(url: item.iconUrl, fallback: Icons.shopping_bag_outlined),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xs + 2,
                  children: [
                    GrowthChip(item.itemType.isEmpty ? '—' : item.itemType),
                    GrowthChip(
                      'adminGrowth.gamify.gemsChip'.tr(
                        args: ['${item.priceGems}'],
                      ),
                    ),
                    GrowthChip(
                      item.stock == null
                          ? 'adminGrowth.gamify.unlimitedStock'.tr()
                          : 'adminGrowth.gamify.inStock'.tr(
                              args: ['${item.stock}'],
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Semantics(
            label: 'adminGrowth.gamify.available'.tr(),
            child: Switch(
              value: item.isAvailable,
              onChanged: onToggle == null ? null : (_) => onToggle!(),
            ),
          ),
        ],
      ),
    );
  }
}
