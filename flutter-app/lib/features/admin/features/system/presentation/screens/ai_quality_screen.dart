import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/admin_async_body.dart';
import '../../data/system_models.dart';
import '../../data/system_repository.dart';
import '../widgets/system_widgets.dart';

/// Quality summary of recent AI answers (`/ai-audit/quality-summary`).
class AiQualityScreen extends StatelessWidget {
  AiQualityScreen({super.key, SystemRepository? repository})
    : repository = repository ?? SystemRepository();

  final SystemRepository repository;

  @override
  Widget build(BuildContext context) {
    return SystemPage(
      title: 'admin.nav.aiQuality'.tr(),
      body: AdminAsyncBody<JsonSnapshot>(
        load: repository.aiQuality,
        isEmpty: (s) => s.isEmpty,
        empty: Center(child: Text('common.noData'.tr())),
        builder: (_, s) =>
            SnapshotView(snapshot: s, title: 'admin.sys.ai.summary'.tr()),
      ),
    );
  }
}
