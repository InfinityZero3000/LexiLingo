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

class LogsRepository {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> getAuditLogs({
    int page = 1,
    String? action,
    String? resourceType,
  }) async {
    final resp = await _api.get('/admin/rbac/audit-logs', params: {
      'page': page,
      'per_page': 30,
      if (action != null && action.isNotEmpty) 'action': action,
      if (resourceType != null && resourceType.isNotEmpty)
        'resource_type': resourceType,
    });
    return {
      'logs': ((resp['logs'] as List?) ?? [])
          .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      'total': resp['total'] ?? 0,
    };
  }
}
