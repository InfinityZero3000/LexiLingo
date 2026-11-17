import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

import '../../../shared/widgets/admin_async_body.dart';
import '../../system/data/system_models.dart';
import '../../system/data/system_repository.dart';
import '../../system/presentation/widgets/system_widgets.dart';

/// KPIs, content performance and funnels; all reads.
class AnalyticsScreen extends StatelessWidget {
  AnalyticsScreen({super.key, SystemRepository? repository})
    : repository = repository ?? SystemRepository();

  final SystemRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: SystemPage(
        title: 'admin.nav.analytics'.tr(),
        bottom: TabBar(
          tabs: [
            Tab(text: 'admin.sys.analytics.overview'.tr()),
            Tab(text: 'admin.sys.analytics.content'.tr()),
            Tab(text: 'admin.sys.analytics.funnels'.tr()),
          ],
        ),
        body: TabBarView(
          children: [
            _Overview(repository: repository),
            _Content(repository: repository),
            _Funnels(repository: repository),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.repository});
  final SystemRepository repository;

  @override
  Widget build(BuildContext context) {
    return AdminAsyncBody<JsonSnapshot>(
      load: repository.kpis,
      isEmpty: (s) => s.scalars.isEmpty,
      empty: Center(child: Text('common.noData'.tr())),
      builder: (_, s) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: systemPagePadding,
        children: [
          MetricWrap(
            metrics: [for (final e in s.scalars) MetricTile(e.key, e.value)],
          ),
        ],
      ),
    );
  }
}

class _ContentData {
  const _ContentData(this.courses, this.performance, this.vocabulary);
  final List<CoursePopularity> courses;
  final JsonSnapshot performance;
  final JsonSnapshot vocabulary;
}

class _Content extends StatelessWidget {
  const _Content({required this.repository});
  final SystemRepository repository;

  Future<_ContentData> _load() async {
    final results = await Future.wait([
      repository.coursePopularity(),
      repository.contentPerformance(),
      repository.vocabularyEffectiveness(),
    ]);
    return _ContentData(
      results[0] as List<CoursePopularity>,
      results[1] as JsonSnapshot,
      results[2] as JsonSnapshot,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncBody<_ContentData>(
      load: _load,
      builder: (context, d) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: systemPagePadding,
        children: [
          SystemSection(
            title: 'admin.sys.analytics.coursePopularity'.tr(),
            child: d.courses.isEmpty
                ? Text('common.noData'.tr())
                : BarList(
                    items: [
                      for (final c in d.courses.take(10))
                        BarItem(c.title, c.enrollments.toDouble()),
                    ],
                  ),
          ),
          if (!d.performance.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SystemSection(
              title: 'admin.sys.analytics.contentPerformance'.tr(),
              child: Column(
                children: [
                  SnapshotRows(snapshot: d.performance),
                  for (final rows in d.performance.tables.values)
                    SnapshotTable(rows: rows),
                ],
              ),
            ),
          ],
          if (!d.vocabulary.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SystemSection(
              title: 'admin.sys.analytics.vocabulary'.tr(),
              child: Column(
                children: [
                  SnapshotRows(snapshot: d.vocabulary),
                  for (final rows in d.vocabulary.tables.values)
                    SnapshotTable(rows: rows),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FunnelData {
  const _FunnelData(this.activation, this.completion);
  final List<FunnelStep> activation;
  final JsonSnapshot completion;
}

class _Funnels extends StatelessWidget {
  const _Funnels({required this.repository});
  final SystemRepository repository;

  Future<_FunnelData> _load() async {
    final results = await Future.wait([
      repository.activationFunnel(),
      repository.completionFunnel(),
    ]);
    return _FunnelData(
      results[0] as List<FunnelStep>,
      results[1] as JsonSnapshot,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncBody<_FunnelData>(
      load: _load,
      builder: (context, d) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: systemPagePadding,
        children: [
          SystemSection(
            title: 'admin.sys.analytics.activation'.tr(),
            child: d.activation.isEmpty
                ? Text('common.noData'.tr())
                : BarList(
                    items: [
                      for (final s in d.activation)
                        BarItem(
                          s.pctOfFirst == null
                              ? s.label
                              : '${s.label} (${s.pctOfFirst}%)',
                          s.count.toDouble(),
                        ),
                    ],
                  ),
          ),
          if (!d.completion.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SystemSection(
              title: 'admin.sys.analytics.completion'.tr(),
              child: Column(
                children: [
                  SnapshotRows(snapshot: d.completion),
                  for (final rows in d.completion.tables.values)
                    SnapshotTable(rows: rows),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
