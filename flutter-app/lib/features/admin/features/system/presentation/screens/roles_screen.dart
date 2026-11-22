import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';

import '../../../../shared/widgets/admin_async_body.dart';
import '../../data/system_models.dart';
import '../../data/system_repository.dart';
import '../widgets/system_widgets.dart';

/// Roles and what each may do. Editing permissions stays on the web admin.
class RolesScreen extends StatelessWidget {
  RolesScreen({super.key, SystemRepository? repository})
    : repository = repository ?? SystemRepository();

  final SystemRepository repository;

  @override
  Widget build(BuildContext context) {
    return SystemPage(
      title: 'admin.nav.roles'.tr(),
      body: AdminAsyncBody<List<RoleSummary>>(
        load: repository.roles,
        isEmpty: (r) => r.isEmpty,
        empty: Center(child: Text('common.noData'.tr())),
        builder: (context, roles) => ListView(
          padding: systemPagePadding,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              'admin.sys.webOnly'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final role in roles)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _RoleCard(role: role, repository: repository),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  const _RoleCard({required this.role, required this.repository});

  final RoleSummary role;
  final SystemRepository repository;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = widget.role;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: AppRadius.lgAll,
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(role.name, style: theme.textTheme.titleSmall),
                          if (role.description != null)
                            Text(
                              role.description!,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (role.isSystem) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: StatusPill(label: 'admin.sys.roles.system'.tr()),
                      ),
                    ],
                    Icon(_open ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: FutureBuilder<RolePermissions>(
                future: widget.repository.rolePermissions(role.slug),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snap.hasError) {
                    return Text('common.error'.tr());
                  }
                  final byResource = snap.data!.byResource;
                  if (byResource.isEmpty) {
                    return Text('common.noData'.tr());
                  }
                  return Column(
                    children: [
                      for (final e in byResource.entries)
                        KeyValueRow(
                          label: humanizeKey(e.key),
                          value: e.value.join(', '),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
