import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/admin_async_body.dart';
import '../../data/system_models.dart';
import '../../data/system_repository.dart';
import '../widgets/system_widgets.dart';

/// Reminders, product events, agent, celery, backup status and error groups: read only.
class OpsCenterScreen extends StatelessWidget {
  OpsCenterScreen({super.key, SystemRepository? repository})
    : repository = repository ?? SystemRepository();

  final SystemRepository repository;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, Future<JsonSnapshot> Function())>[
      ('admin.sys.ops.reminders', () => repository.ops('reminders')),
      (
        'admin.sys.ops.productEvents',
        () => repository.ops('product-events', days: 7),
      ),
      ('admin.sys.ops.contentAgent', () => repository.ops('content-agent')),
      ('admin.sys.ops.celery', () => repository.ops('celery')),
      ('admin.sys.ops.backups', () => repository.ops('backups')),
      ('admin.sys.ops.errors', () => repository.ops('errors')),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: SystemPage(
        title: 'admin.nav.ops'.tr(),
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
