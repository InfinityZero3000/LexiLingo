import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/confirm_dialog.dart';
import 'package:lexilingo_app/core/widgets/filter_chip_bar.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_paged_list_view.dart';
import '../../../shared/widgets/admin_screen_scaffold.dart';
import '../../../shared/widgets/open_in_web_admin_tile.dart';
import '../../gem_ledger/data/gem_ledger_repository.dart';
import '../data/users_repository.dart';
import 'gift_gems_sheet.dart';
import 'user_detail_tabs.dart';
import 'user_format.dart';
import 'users_screen.dart' show adminRoleLabelKey;

enum _UserTab { overview, wallet, xp, items }

class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({
    super.key,
    required this.userId,
    this.repository,
    this.gemRepository,
  });

  final String userId;

  /// Replace the real repositories in tests.
  final UsersRepository? repository;
  final GemLedgerRepository? gemRepository;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late final UsersRepository _repo = widget.repository ?? UsersRepository();
  late final GemLedgerRepository _gems =
      widget.gemRepository ?? GemLedgerRepository();

  late Future<AdminUserDetail> _user = _repo.getUser(widget.userId);
  late Future<List<UserActivityEntry>> _activity = _repo.getActivity(
    widget.userId,
  );
  Future<ItemsAndPremium>? _items;
  _UserTab _tab = _UserTab.overview;
  bool _acting = false;

  void _reload() => setState(() {
    _user = _repo.getUser(widget.userId);
    _activity = _repo.getActivity(widget.userId);
    _items = null;
  });

  Future<ItemsAndPremium> _loadItems() async {
    final results = await (
      _repo.getPremium(widget.userId),
      _repo.getInventory(widget.userId),
    ).wait;
    return (premium: results.$1, items: results.$2);
  }

  void _notice(String text, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: TextStyle(
            color: error ? scheme.onError : scheme.onInverseSurface,
          ),
        ),
        backgroundColor: error ? scheme.error : scheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleActive(AdminUserDetail user) async {
    final next = !user.isActive;
    final ok = await showConfirm(
      context,
      title:
          (next
                  ? 'admin.users.detail.activateTitle'
                  : 'admin.users.detail.suspendTitle')
              .tr(),
      message:
          (next
                  ? 'admin.users.detail.activateBody'
                  : 'admin.users.detail.suspendBody')
              .tr(namedArgs: {'name': user.shownName}),
      confirmLabel:
          (next ? 'admin.users.detail.activate' : 'admin.users.detail.suspend')
              .tr(),
      danger: !next,
    );
    if (!ok || !mounted) return;
    setState(() => _acting = true);
    try {
      await _repo.setActive(user.id, next);
      _notice(
        (next ? 'admin.users.detail.activated' : 'admin.users.detail.suspended')
            .tr(),
      );
      _reload();
    } catch (e) {
      _notice(AdminApiError.from(e).message.resolve(), error: true);
    }
    if (mounted) setState(() => _acting = false);
  }

  Future<void> _gift(AdminUserDetail user) async {
    final sent = await showGiftGemsSheet(
      context,
      recipientName: user.shownName,
      loadUsage: () async => (await _gems.getLimits()).usage,
      send: (amount, reason) =>
          _repo.giftGems(user.id, amount: amount, reason: reason),
    );
    if (sent) _notice('admin.users.gift.sent'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<AdminPermissions>();
    return AdminScreenScaffold(
      pushed: true,
      title: 'admin.users.detail.title'.tr(),
      body: AdminFutureView<AdminUserDetail>(
        future: _user,
        onRetry: _reload,
        builder: (context, user) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: SegmentedTabs<_UserTab>(
                selected: _tab,
                onChanged: (tab) => setState(() => _tab = tab),
                options: [
                  FilterOption(
                    value: _UserTab.overview,
                    label: 'admin.users.detail.tabOverview'.tr(),
                  ),
                  FilterOption(
                    value: _UserTab.wallet,
                    label: 'admin.users.detail.tabWallet'.tr(),
                  ),
                  FilterOption(
                    value: _UserTab.xp,
                    label: 'admin.users.detail.tabXp'.tr(),
                  ),
                  FilterOption(
                    value: _UserTab.items,
                    label: 'admin.users.detail.tabItems'.tr(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                _UserTab.overview => _Overview(
                  user: user,
                  activity: _activity,
                  acting: _acting,
                  canSuspend: permissions.can('users:update'),
                  canGift: permissions.can('gifts:grant'),
                  onToggle: () => _toggleActive(user),
                  onGift: () => _gift(user),
                  onRetryActivity: () => setState(() {
                    _activity = _repo.getActivity(widget.userId);
                  }),
                ),
                _UserTab.wallet => UserWalletTab(
                  key: ValueKey('wallet-${user.id}-${_user.hashCode}'),
                  userId: user.id,
                  repository: _repo,
                ),
                _UserTab.xp => UserXpTab(userId: user.id, repository: _repo),
                _UserTab.items => AdminFutureView<ItemsAndPremium>(
                  future: _items ??= _loadItems(),
                  onRetry: () => setState(() => _items = null),
                  builder: (context, data) => UserItemsTab(data: data),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.user,
    required this.activity,
    required this.acting,
    required this.canSuspend,
    required this.canGift,
    required this.onToggle,
    required this.onGift,
    required this.onRetryActivity,
  });

  final AdminUserDetail user;
  final Future<List<UserActivityEntry>> activity;
  final bool acting, canSuspend, canGift;
  final VoidCallback onToggle, onGift, onRetryActivity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatar = user.avatarUrl?.trim();
    final hasAvatar = avatar != null && avatar.isNotEmpty;
    final initial = user.shownName.isEmpty
        ? '?'
        : user.shownName.characters.first.toUpperCase();

    Widget stat(String key, int value, IconData icon) =>
        StatCard(label: key.tr(), value: '$value', icon: icon);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadius.lgAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    foregroundImage: hasAvatar ? NetworkImage(avatar) : null,
                    onForegroundImageError: hasAvatar ? (_, __) {} : null,
                    child: Text(initial, style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.shownName,
                          style: theme.textTheme.sectionTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          user.email,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  StatusPill(
                    label: user.isActive
                        ? 'admin.users.statusActive'.tr()
                        : 'admin.users.statusSuspended'.tr(),
                    tone: user.isActive
                        ? StatusTone.success
                        : StatusTone.neutral,
                  ),
                  StatusPill(
                    label: adminRoleLabelKey(user.roleLevel).tr(),
                    tone: user.roleLevel > 0
                        ? StatusTone.info
                        : StatusTone.neutral,
                  ),
                  StatusPill(
                    label: user.isVerified
                        ? 'admin.users.detail.verified'.tr()
                        : 'admin.users.detail.unverified'.tr(),
                    tone: user.isVerified
                        ? StatusTone.success
                        : StatusTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Fact(
                label: 'admin.users.detail.joined'.tr(),
                value: formatAdminDate(user.createdAt),
              ),
              _Fact(
                label: 'admin.users.detail.lastLogin'.tr(),
                value: formatAdminDateTime(
                  user.lastLogin,
                  fallback: 'admin.users.detail.never'.tr(),
                ),
              ),
              if (user.providers.isNotEmpty)
                _Fact(
                  label: 'admin.users.detail.provider'.tr(),
                  value: user.providers.join(', '),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            mainAxisExtent: 104,
          ),
          children: [
            stat(
              'admin.users.detail.totalXp',
              user.totalXp,
              Icons.star_outline,
            ),
            stat(
              'admin.users.detail.coursesEnrolled',
              user.coursesEnrolled,
              Icons.menu_book_outlined,
            ),
            stat(
              'admin.users.detail.coursesCompleted',
              user.coursesCompleted,
              Icons.check_circle_outline,
            ),
            stat(
              'admin.users.detail.lessonsCompleted',
              user.lessonsCompleted,
              Icons.school_outlined,
            ),
          ],
        ),
        if (canSuspend || canGift) ...[
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              if (canSuspend)
                Expanded(
                  child: user.isActive
                      ? OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, kMinTapTarget),
                            foregroundColor: scheme.error,
                            side: BorderSide(color: scheme.error),
                          ),
                          onPressed: acting ? null : onToggle,
                          icon: const Icon(Icons.pause_circle_outline),
                          label: Text('admin.users.detail.suspend'.tr()),
                        )
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, kMinTapTarget),
                          ),
                          onPressed: acting ? null : onToggle,
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text('admin.users.detail.activate'.tr()),
                        ),
                ),
              if (canSuspend && canGift) const SizedBox(width: AppSpacing.md),
              if (canGift)
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, kMinTapTarget),
                    ),
                    onPressed: acting ? null : onGift,
                    icon: const Icon(Icons.card_giftcard_outlined),
                    label: Text('admin.users.gift.title'.tr()),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          'admin.users.detail.activityTitle'.tr(),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        FutureBuilder<List<UserActivityEntry>>(
          future: activity,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      AdminApiError.from(snapshot.error!).message.resolve(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                    ),
                    onPressed: onRetryActivity,
                    child: Text('common.retry'.tr()),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return Text(
                'admin.users.detail.activityEmpty'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              );
            }
            return Column(
              children: [
                for (final entry in entries.take(30))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: LedgerRow(
                      title: entry.description,
                      subtitle: formatAdminDate(entry.date),
                      amount: entry.xpEarned,
                      trailingNote: entry.xpEarned == 0 ? null : 'XP',
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        OpenInWebAdminTile(
          body: 'admin.users.detail.webOnlyBody'.tr(),
          path: '/admin/users',
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
