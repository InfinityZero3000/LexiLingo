import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/admin_async_body.dart';
import '../../system/data/system_models.dart';
import '../../system/data/system_repository.dart';
import '../../system/presentation/widgets/system_widgets.dart';

/// Server, services, database, request and integration health. The route is
/// guarded by `ops:read` in `adminNavItems`.
class SystemHealthScreen extends StatelessWidget {
  SystemHealthScreen({super.key, SystemRepository? repository})
    : repository = repository ?? SystemRepository();

  final SystemRepository repository;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, Future<JsonSnapshot> Function())>[
      ('admin.sys.health.system', () => repository.monitoring('system')),
      ('admin.sys.health.services', () => repository.monitoring('services')),
      ('admin.sys.health.database', () => repository.monitoring('db-stats')),
      (
        'admin.sys.health.requests',
        () => repository.monitoring('request-stats'),
      ),
      ('admin.sys.health.integrations', repository.integrations),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: SystemPage(
        title: 'admin.nav.health'.tr(),
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in tabs) Tab(text: t.$1.tr())],
        ),
        body: TabBarView(
          children: [
            for (final t in tabs)
              AdminAsyncBody<JsonSnapshot>(
                load: t.$2,
                isEmpty: (s) => s.isEmpty,
                empty: Center(child: Text('common.noData'.tr())),
                builder: (_, s) => SnapshotView(snapshot: s, title: t.$1.tr()),
              ),
          ],
        ),
      ),
    );
  }
}
