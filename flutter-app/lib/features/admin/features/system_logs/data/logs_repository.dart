import 'package:lexilingo_app/core/state/paginated_list_controller.dart';

import '../../../core/network/api_client.dart';

class AuditLogEntry {
  final String createdAt;
  final String action;
  final String resourceType;
  final String? resourceId;
  final String? details;
  final String? userId;

  const AuditLogEntry({
    required this.createdAt,
    required this.action,
    required this.resourceType,
    this.resourceId,
    this.details,
    this.userId,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> j) => AuditLogEntry(
    createdAt: j['created_at']?.toString() ?? '',
    action: j['action']?.toString() ?? '',
    resourceType: j['resource_type']?.toString() ?? '',
    resourceId: j['resource_id']?.toString(),
    details: j['details']?.toString(),
    userId: j['user_id']?.toString(),
  );
}

class AuditFacets {
  const AuditFacets({this.actions = const [], this.resourceTypes = const []});

  factory AuditFacets.fromJson(dynamic body) {
    final map = body is Map ? body : const {};
    List<String> read(String key) => [
      for (final v in (map[key] is List ? map[key] as List : const []))
        if (v != null) '$v',
    ];
    return AuditFacets(
      actions: read('actions'),
      resourceTypes: read('resource_types'),
    );
  }

  final List<String> actions;
  final List<String> resourceTypes;
}

/// Audit log reads only; the CSV export stays on the web admin.
class LogsRepository {
  LogsRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  /// `{logs, total, page, per_page}`: the audit endpoint's own page shape.
  Future<PageResult<AuditLogEntry>> fetchPage(
    PageRequest request,
    Map<String, Object?> filters,
  ) async {
    final body = await _api.getData(
      '/admin/rbac/audit-logs',
      params: {
        ...PaginationStyle.perPage.query(request),
        for (final e in filters.entries)
          if (e.value != null && '${e.value}'.isNotEmpty) e.key: e.value,
      },
    );
    final map = body is Map ? body : const {};
    final logs = map['logs'] is List ? map['logs'] as List : const [];
    return PageResult(
      items: [
        for (final l in logs)
          if (l is Map) AuditLogEntry.fromJson(Map<String, dynamic>.from(l)),
      ],
      total: (map['total'] as num?)?.toInt(),
    );
  }

  Future<AuditFacets> facets() async =>
      AuditFacets.fromJson(await _api.getData('/admin/rbac/audit-logs/facets'));
}
