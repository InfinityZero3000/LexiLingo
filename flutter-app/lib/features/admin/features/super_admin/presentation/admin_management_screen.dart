import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';

import '../../../shared/widgets/admin_async_body.dart';
import '../../system/data/system_repository.dart';
import '../../system/presentation/widgets/system_widgets.dart';

/// Who holds an admin role. Granting or removing a role is deliberately not
/// possible from the phone; it stays on the web admin.
class AdminManagementScreen extends StatelessWidget {
  AdminManagementScreen({super.key, SystemRepository? repository})
    : repository = repository ?? SystemRepository();

  final SystemRepository repository;

  @override
  Widget build(BuildContext context) {
    return SystemPage(
      title: 'admin.nav.adminManagement'.tr(),
      body: AdminAsyncBody<List<Map<String, dynamic>>>(
        load: repository.admins,
        isEmpty: (a) => a.isEmpty,
        empty: Center(child: Text('common.noData'.tr())),
        builder: (context, admins) {
          final theme = Theme.of(context);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: systemPagePadding,
            children: [
              Text(
                'admin.sys.admins.webOnly'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final a in admins)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${a['full_name'] ?? a['name'] ?? a['username'] ?? a['email'] ?? ''}',
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                '${a['email'] ?? ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        StatusPill(
                          label: _isSuper(a)
                              ? 'admin.shell.roleSuper'.tr()
                              : 'admin.shell.roleAdmin'.tr(),
                          tone: _isSuper(a)
                              ? StatusTone.info
                              : StatusTone.neutral,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _isSuper(Map<String, dynamic> a) =>
      a['is_super_admin'] == true ||
      (a['role_level'] as num? ?? 0) >= 2 ||
      a['role'] == 2;
}
