import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import '../../../shared/widgets/admin_paged_list_view.dart';
import '../data/users_repository.dart';
import 'user_format.dart';

/// Row used by the wallet and XP ledgers: a title, a muted line and a signed
/// amount that reads green for credit and red for debit.
class LedgerRow extends StatelessWidget {
  const LedgerRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.trailingNote,
  });

  final String title;
  final String subtitle;
  final int amount;
  final String? trailingNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = amount < 0 ? scheme.error : context.status.success;
    return Container(
      constraints: const BoxConstraints(minHeight: kMinTapTarget),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                signedAmount(amount),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (trailingNote != null)
                Text(
                  trailingNote!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _summaryRow(List<Widget> cards) => Padding(
  padding: const EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.sm,
    AppSpacing.lg,
    AppSpacing.sm,
  ),
  child: Row(
    children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpacing.md),
        Expanded(child: cards[i]),
      ],
    ],
  ),
);

/// Gem balance and the ledger behind it. Read-only: correcting a balance is a
/// super-admin job on the web admin.
class UserWalletTab extends StatefulWidget {
  const UserWalletTab({
    super.key,
    required this.userId,
    required this.repository,
  });

  final String userId;
  final UsersRepository repository;

  @override
  State<UserWalletTab> createState() => _UserWalletTabState();
}

class _UserWalletTabState extends State<UserWalletTab> {
  final _summary = ValueNotifier<WalletPage?>(null);
  late final AdminPageFetcher<WalletTransaction> _fetcher = AdminPageFetcher((
    request,
    _,
  ) async {
    final page = await widget.repository.getWallet(widget.userId, request);
    if (request.index == 0) _summary.value = page;
    return PageResult(items: page.transactions, total: page.total);
  });
  late final PaginatedListController<WalletTransaction> _controller =
      PaginatedListController(fetcher: _fetcher);

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fetcher.total.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<WalletPage?>(
          valueListenable: _summary,
          builder: (context, page, _) => page == null
              ? const SizedBox.shrink()
              : _summaryRow([
                  StatCard(
                    label: 'admin.users.wallet.balance'.tr(),
                    value: '${page.balance}',
                    icon: Icons.diamond_outlined,
                    note: 'admin.users.wallet.earnedSpent'.tr(
                      namedArgs: {
                        'earned': '${page.totalEarned}',
                        'spent': '${page.totalSpent}',
                      },
                    ),
                  ),
                ]),
        ),
        Expanded(
          child: AdminPagedListView<WalletTransaction>(
            controller: _controller,
            fetcher: _fetcher,
            emptyIcon: Icons.diamond_outlined,
            emptyTitle: 'admin.users.wallet.empty'.tr(),
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, tx, _) => LedgerRow(
              title: tx.description?.isNotEmpty == true
                  ? tx.description!
                  : (tx.source ?? tx.type),
              subtitle: formatAdminDateTime(tx.createdAt),
              amount: tx.amount,
              trailingNote: 'admin.users.wallet.after'.tr(
                namedArgs: {'balance': '${tx.balanceAfter}'},
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// XP total and the awards behind it.
class UserXpTab extends StatefulWidget {
  const UserXpTab({super.key, required this.userId, required this.repository});

  final String userId;
  final UsersRepository repository;

  @override
  State<UserXpTab> createState() => _UserXpTabState();
}

class _UserXpTabState extends State<UserXpTab> {
  final _summary = ValueNotifier<XpPage?>(null);
  late final AdminPageFetcher<XpTransaction> _fetcher = AdminPageFetcher((
    request,
    _,
  ) async {
    final page = await widget.repository.getXp(widget.userId, request);
    if (request.index == 0) _summary.value = page;
    return PageResult(items: page.transactions, total: page.total);
  });
  late final PaginatedListController<XpTransaction> _controller =
      PaginatedListController(fetcher: _fetcher);

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fetcher.total.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<XpPage?>(
          valueListenable: _summary,
          builder: (context, page, _) => page == null
              ? const SizedBox.shrink()
              : _summaryRow([
                  StatCard(
                    label: 'admin.users.xp.total'.tr(),
                    value: '${page.totalXp}',
                    icon: Icons.star_outline,
                  ),
                ]),
        ),
        Expanded(
          child: AdminPagedListView<XpTransaction>(
            controller: _controller,
            fetcher: _fetcher,
            emptyIcon: Icons.star_outline,
            emptyTitle: 'admin.users.xp.empty'.tr(),
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, tx, _) => LedgerRow(
              title: tx.sourceDetail?.isNotEmpty == true
                  ? '${tx.source} · ${tx.sourceDetail}'
                  : tx.source,
              subtitle: formatAdminDateTime(tx.createdAt),
              amount: tx.amount,
              trailingNote: tx.multiplier != 1
                  ? 'admin.users.xp.multiplier'.tr(
                      namedArgs: {'value': tx.multiplier.toStringAsFixed(1)},
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

typedef ItemsAndPremium = ({PremiumStatus premium, List<InventoryEntry> items});

/// Premium status and shop inventory, both read-only: granting or revoking
/// premium is a super-admin job on the web admin.
class UserItemsTab extends StatelessWidget {
  const UserItemsTab({super.key, required this.data});

  final ItemsAndPremium data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final premium = data.premium;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
                  Expanded(
                    child: Text(
                      'admin.users.items.premium'.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: StatusPill(
                      label: premium.isActive
                          ? 'admin.users.items.premiumActive'.tr()
                          : 'admin.users.items.premiumInactive'.tr(),
                      tone: premium.isActive
                          ? StatusTone.success
                          : StatusTone.neutral,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!premium.exists)
                Text(
                  'admin.users.items.premiumNone'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else ...[
                if (premium.source != null)
                  _line(
                    context,
                    'admin.users.items.source'.tr(
                      namedArgs: {'source': premium.source!},
                    ),
                  ),
                if (premium.expiresAt != null)
                  _line(
                    context,
                    'admin.users.items.until'.tr(
                      namedArgs: {'date': formatAdminDate(premium.expiresAt)},
                    ),
                  ),
              ],
              if (premium.forceEnabled)
                _line(context, 'admin.users.items.forceEnabled'.tr()),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'admin.users.items.inventory'.tr(),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (data.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              'admin.users.items.empty'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final item in data.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                constraints: const BoxConstraints(minHeight: kMinTapTarget),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: AppRadius.lgAll,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: theme.textTheme.titleSmall),
                          if (item.isActive)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              child: StatusPill(
                                label: 'admin.users.items.equipped'.tr(),
                                tone: StatusTone.info,
                              ),
                            ),
                          Text(
                            [
                              item.itemType,
                              if (item.expiresAt != null)
                                'admin.users.items.until'.tr(
                                  namedArgs: {
                                    'date': formatAdminDate(item.expiresAt),
                                  },
                                ),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '×${item.quantity}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _line(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
