import '../../../core/network/api_client.dart';
import 'system_models.dart';

/// Read-only calls behind the system screens. Nothing here writes.
class SystemRepository {
  SystemRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<JsonSnapshot> _snapshot(
    String path, {
    Map<String, dynamic>? params,
  }) async => JsonSnapshot.from(await _api.getData(path, params: params));

  Future<JsonSnapshot> ops(String name, {int? days}) => _snapshot(
    '/admin/ops/$name',
    params: days == null ? null : {'days': days},
  );

  Future<JsonSnapshot> monitoring(String name) =>
      _snapshot('/admin/monitoring/$name');

  Future<JsonSnapshot> integrations() => _snapshot('/health/integrations');

  Future<JsonSnapshot> systemInfo() => _snapshot('/admin/system-info');

  Future<JsonSnapshot> aiQuality({int limit = 50}) =>
      _snapshot('/ai-audit/quality-summary', params: {'limit': limit});

  Future<JsonSnapshot> kpis() async {
    final body = await _api.getData('/admin/analytics/dashboard/kpis');
    final map = body is Map ? body : const {};
    return JsonSnapshot.from(map['kpis'] ?? body);
  }

  Future<List<CoursePopularity>> coursePopularity() async {
    final body = await _api.getData(
      '/admin/analytics/dashboard/course-popularity',
    );
    final data = body is Map ? body['data'] : body;
    return [
      for (final r in (data is List ? data : const []))
        if (r is Map) CoursePopularity.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  Future<JsonSnapshot> completionFunnel() =>
      _snapshot('/admin/analytics/dashboard/completion-funnel');

  Future<List<FunnelStep>> activationFunnel() async => parseFunnelSteps(
    await _api.getData('/admin/analytics/dashboard/activation-funnel'),
  );

  Future<JsonSnapshot> contentPerformance() =>
      _snapshot('/admin/analytics/content-performance');

  Future<JsonSnapshot> vocabularyEffectiveness() =>
      _snapshot('/admin/analytics/vocabulary-effectiveness');

  Future<List<RoleSummary>> roles() async {
    final body = await _api.getData('/admin/rbac/roles');
    return [
      for (final r in extractList(body))
        RoleSummary.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  Future<RolePermissions> rolePermissions(String slug) async =>
      RolePermissions.fromJson(await _api.getData('/admin/rbac/roles/$slug'));

  /// Users holding admin (1) and super admin (2) roles, read only.
  Future<List<Map<String, dynamic>>> admins() async {
    final out = <Map<String, dynamic>>[];
    for (final role in const [1, 2]) {
      final body = await _api.getData(
        '/admin/users',
        params: {'page': 1, 'page_size': 100, 'role': role},
      );
      out.addAll(extractList(body).map((e) => Map<String, dynamic>.from(e)));
    }
    return out;
  }
}

/// The maps in a list body, whichever of the usual shapes it came in.
List<Map> extractList(dynamic body) {
  dynamic list = body;
  if (body is Map) {
    for (final k in const ['data', 'items', 'users', 'results']) {
      if (body[k] is List) {
        list = body[k];
        break;
      }
      if (body[k] is Map) return extractList(body[k]);
    }
  }
  return list is List ? list.whereType<Map>().toList() : const [];
}
