import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/paginated_list_view.dart';
import 'package:lexilingo_app/core/widgets/filter_chip_bar.dart';

import '../../../shared/widgets/admin_error_view.dart';
import '../../system/presentation/widgets/system_widgets.dart';
import '../data/logs_repository.dart';

/// Audit trail: paged list, filtered by the action and resource that occur.
class LogsScreen extends StatefulWidget {
  LogsScreen({super.key, LogsRepository? repository})
    : repository = repository ?? LogsRepository();

  final LogsRepository repository;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  late final PaginatedListController<AuditLogEntry> _controller =
      PaginatedListController<AuditLogEntry>(
        fetcher: FunctionPageFetcher(widget.repository.fetchPage),
        pageSize: 30,
      );
  AuditFacets _facets = const AuditFacets();
  Object? _facetError;

  @override
  void initState() {
    super.initState();
    _loadFacets();
  }

  Future<void> _loadFacets() async {
    try {
      final facets = await widget.repository.facets();
      if (mounted) setState(() => _facets = facets);
    } catch (e) {
      if (mounted) setState(() => _facetError = e);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The list cannot be read without rbac:read, so a refused facet call is the
    // whole screen's answer rather than an empty filter bar.
    if (_facetError != null && _facets.actions.isEmpty) {
      return SystemPage(
        title: 'admin.nav.logs'.tr(),
        body: AdminErrorView(
          error: _facetError!,
          onRetry: () {
            setState(() => _facetError = null);
            _loadFacets();
          },
        ),
      );
    }
    return SystemPage(
      title: 'admin.nav.logs'.tr(),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final action = _controller.filters['action'] as String?;
          final resource = _controller.filters['resource_type'] as String?;
          return PaginatedListView<AuditLogEntry>(
            controller: _controller,
            emptyTitle: 'admin.sys.audit.empty'.tr(),
            emptyIcon: Icons.manage_search_outlined,
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.md),
                FilterChipBar<String>(
                  options: [
                    for (final a in _facets.actions)
                      FilterOption(value: a, label: a),
                  ],
                  selected: action,
                  allowClear: true,
                  onSelected: (v) => _controller.setFilter('action', v),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilterChipBar<String>(
                  options: [
                    for (final r in _facets.resourceTypes)
                      FilterOption(value: r, label: r),
                  ],
                  selected: resource,
                  allowClear: true,
                  onSelected: (v) => _controller.setFilter('resource_type', v),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
            itemBuilder: (context, log, _) => _LogTile(log: log),
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final AuditLogEntry log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(log.action, style: theme.textTheme.titleSmall),
          Text(
            [
              log.resourceType,
              if (log.resourceId != null) log.resourceId!,
            ].join(' · '),
            style: muted,
          ),
          if (log.details != null && log.details!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                log.details!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(log.createdAt, style: muted),
        ],
      ),
    );
  }
}
