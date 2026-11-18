import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import '../../../core/network/api_client.dart';
import 'gem_models.dart';

export 'gem_models.dart';

const _grantsPath = '/admin/gem-grants';
const _limitsPath = '/admin/gem-limits';

Map<String, dynamic> _asMap(dynamic body) =>
    body is Map ? Map<String, dynamic>.from(body) : const {};

/// Read-only view of the gem ledger. Changing the caps (`PUT /gem-limits`) is a
/// super-admin job on the web admin.
class GemLedgerRepository {
  GemLedgerRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  /// One page of grants, newest first. [filters] may hold `kind` (`gift` or
  /// `adjust`), `date_from` and `date_to` (`yyyy-MM-dd`). A plain admin only
  /// sees their own grants; the backend decides.
  Future<PageResult<GemGrant>> listGrants(
    PageRequest request,
    Map<String, Object?> filters,
  ) async {
    final data = _asMap(
      await _api.getData(
        _grantsPath,
        params: {
          'limit': request.limit,
          'offset': request.offset,
          for (final key in const ['kind', 'date_from', 'date_to'])
            if (filters[key] != null) key: filters[key],
        },
      ),
    );
    final items = data['items'];
    final total = data['total'];
    return PageResult(
      items: items is List
          ? items
                .whereType<Map>()
                .map((e) => GemGrant.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : <GemGrant>[],
      total: total is num ? total.toInt() : null,
    );
  }

  Future<GemLimits> getLimits() async =>
      GemLimits.fromJson(_asMap(await _api.getData(_limitsPath)));
}
