import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/network/envelope.dart';
import '../constants/api_endpoints.dart';
import '../network/admin_api_error.dart';
import '../network/api_client.dart';

enum AdminPermissionsStatus { idle, loading, ready, failed }

/// What the signed-in admin may do, from `GET /admin/rbac/me/permissions`
/// (`{all, permissions: ["resource:action", ...]}`).
///
/// This only decides what the app shows; the backend enforces every call.
/// `resource:manage` covers every action on that resource, and `all` (super
/// admin) covers everything.
class AdminPermissions extends ChangeNotifier {
  AdminPermissions({Future<dynamic> Function()? fetch})
    : _fetch = fetch ?? _fetchFromApi;

  final Future<dynamic> Function() _fetch;

  AdminPermissionsStatus _status = AdminPermissionsStatus.idle;
  bool _all = false;
  Set<String> _slugs = const {};
  AdminApiError? _error;

  AdminPermissionsStatus get status => _status;
  bool get isReady => _status == AdminPermissionsStatus.ready;
  bool get isLoading => _status == AdminPermissionsStatus.loading;
  bool get hasAll => _all;
  AdminApiError? get error => _error;

  static Future<dynamic> _fetchFromApi() =>
      ApiClient.instance.getData(ApiEndpoints.myPermissions);

  bool can(String slug) {
    if (_all) return true;
    if (_slugs.contains(slug)) return true;
    final colon = slug.indexOf(':');
    if (colon <= 0) return false;
    return _slugs.contains('${slug.substring(0, colon)}:manage');
  }

  /// True when the role holds any permission on [resource].
  bool canAny(String resource) {
    if (_all) return true;
    return _slugs.any((s) => s.startsWith('$resource:'));
  }

  Future<void> load() async {
    _status = AdminPermissionsStatus.loading;
    _error = null;
    notifyListeners();
    try {
      apply(await _fetch());
    } catch (e) {
      _all = false;
      _slugs = const {};
      _error = AdminApiError.from(e);
      _status = AdminPermissionsStatus.failed;
      notifyListeners();
    }
  }

  @visibleForTesting
  void apply(dynamic body) {
    final data = unwrapEnvelope(body);
    final map = data is Map ? data : const {};
    _all = map['all'] == true;
    final list = map['permissions'];
    _slugs = list is List
        ? list.map((e) => e.toString()).toSet()
        : const <String>{};
    _status = AdminPermissionsStatus.ready;
    notifyListeners();
  }

  void clear() {
    _all = false;
    _slugs = const {};
    _error = null;
    _status = AdminPermissionsStatus.idle;
    notifyListeners();
  }
}
