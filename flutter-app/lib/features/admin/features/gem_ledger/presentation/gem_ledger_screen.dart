import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/filter_chip_bar.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import '../../../shared/widgets/admin_paged_list_view.dart';
import '../../../shared/widgets/admin_screen_scaffold.dart';
import '../../../shared/widgets/open_in_web_admin_tile.dart';
import '../../users/presentation/user_format.dart';
import '../data/gem_ledger_repository.dart';

const _anyKind = 'all';

class GemLedgerScreen extends StatefulWidget {
  const GemLedgerScreen({super.key, this.repository});

  /// Replaces the real repository in tests.
  final GemLedgerRepository? repository;

  @override
  State<GemLedgerScreen> createState() => _GemLedgerScreenState();
}

class _GemLedgerScreenState extends State<GemLedgerScreen> {
  late final GemLedgerRepository _repo =
      widget.repository ?? GemLedgerRepository();
  late final AdminPageFetcher<GemGrant> _fetcher = AdminPageFetcher(
    _repo.listGrants,
  );
  late final PaginatedListController<GemGrant> _controller =
      PaginatedListController(fetcher: _fetcher);
  late Future<GemLimits> _limits = _repo.getLimits();
  String _kind = _anyKind;

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fetcher.total.dispose();
    super.dispose();
  }

  void _setKind(String? kind) {
    setState(() => _kind = kind ?? _anyKind);
    _controller.setFilters({if (_kind != _anyKind) 'kind': _kind});
  }

  @override
  Widget build(BuildContext context) {
    return AdminScreenScaffold(
      title: 'admin.gems.title'.tr(),
      body: Column(
        children: [
          FutureBuilder<GemLimits>(
            future: _limits,
            builder: (context, snapshot) => _LimitsCard(
              snapshot: snapshot,
              onRetry: () => setState(() {
                _limits = _repo.getLimits();
              }),
            ),
          ),
          FilterChipBar<String>(
            options: [
              FilterOption(value: _anyKind, label: 'admin.gems.filterAll'.tr()),
              FilterOption(value: 'gift', label: 'admin.gems.kindGift'.tr()),
              FilterOption(
                value: 'adjust',
                label: 'admin.gems.kindAdjust'.tr(),
              ),
            ],
            selected: _kind,
            onSelected: _setKind,
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: AdminPagedListView<GemGrant>(
              controller: _controller,
              fetcher: _fetcher,
              emptyIcon: Icons.diamond_outlined,
              emptyTitle: 'admin.gems.emptyTitle'.tr(),
              emptyDescription: 'admin.gems.emptyBody'.tr(),
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, grant, _) => GrantTile(grant: grant),
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitsCard extends StatelessWidget {
  const _LimitsCard({required this.snapshot, required this.onRetry});

  final AsyncSnapshot<GemLimits> snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final limits = snapshot.data;
    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'admin.gems.limitsFailed'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              ),
              onPressed: onRetry,
              child: Text('common.retry'.tr()),
            ),
          ],
        ),
      );
    }
    final usage = limits?.usage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StatCard(
                  loading: usage == null,
                  label: 'admin.gems.remainingToday'.tr(),
                  value: '${usage?.remainingToday ?? 0}',
                  icon: Icons.diamond_outlined,
                  note: usage == null
                      ? null
                      : 'admin.gems.budgetNote'.tr(
                          namedArgs: {
                            'spent': '${usage.spentToday}',
                            'budget': '${usage.dailyBudget}',
                          },
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  loading: usage == null,
                  label: 'admin.gems.perGift'.tr(),
                  value: '${usage?.maxPerAction ?? 0}',
                  icon: Icons.card_giftcard_outlined,
                ),
              ),
            ],
          ),
          if (limits?.config != null) ...[
            const SizedBox(height: AppSpacing.md),
            OpenInWebAdminTile(
              body: 'admin.gems.webOnlyBody'.tr(),
              path: '/admin/gem-ledger',
            ),
          ],
        ],
      ),
    );
  }
}

class GrantTile extends StatelessWidget {
  const GrantTile({super.key, required this.grant});

  final GemGrant grant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final debit = grant.amount < 0;
    return Container(
      constraints: const BoxConstraints(minHeight: kMinTapTarget),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        grant.recipient,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusPill(
                      label: grant.isAdjustment
                          ? 'admin.gems.kindAdjust'.tr()
                          : 'admin.gems.kindGift'.tr(),
                      tone: grant.isAdjustment
                          ? StatusTone.warning
                          : StatusTone.info,
                    ),
                  ],
                ),
                if (grant.reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      grant.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    formatAdminDateTime(grant.createdAt),
                    if (grant.actorName != null)
                      'admin.gems.by'.tr(namedArgs: {'name': grant.actorName!}),
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            signedAmount(grant.amount),
            style: theme.textTheme.titleSmall?.copyWith(
              color: debit ? scheme.error : context.status.success,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
