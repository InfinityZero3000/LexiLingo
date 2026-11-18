import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

import '../../../shared/widgets/admin_async_body.dart';
import '../../system/data/system_models.dart';
import '../../system/data/system_repository.dart';
import '../../system/presentation/widgets/system_widgets.dart';

/// Server configuration as the backend reports it. Changing it is done on the
/// web admin, where the change is reviewed; this screen never writes.
class SystemSettingsScreen extends StatelessWidget {
  SystemSettingsScreen({super.key, SystemRepository? repository})
    : repository = repository ?? SystemRepository();

  final SystemRepository repository;

  @override
  Widget build(BuildContext context) {
    return SystemPage(
      title: 'admin.nav.config'.tr(),
      body: AdminAsyncBody<JsonSnapshot>(
        load: repository.systemInfo,
        isEmpty: (s) => s.isEmpty,
        empty: Center(child: Text('common.noData'.tr())),
        builder: (context, s) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: systemPagePadding,
          children: [
            Text(
              'admin.sys.webOnly'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            SystemSection(
              title: 'admin.sys.config.info'.tr(),
              child: SnapshotRows(snapshot: s, limit: 60),
            ),
          ],
        ),
      ),
    );
  }
}
