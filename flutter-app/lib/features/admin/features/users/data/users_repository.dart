import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import 'user_models.dart';

export 'user_models.dart';

/// How `GET /admin/users` may be ordered.
enum UserSort {
  newest('created_at', 'desc'),
  recentLogin('last_login', 'desc'),
  topXp('total_xp', 'desc'),
  email('email', 'asc');

  const UserSort(this.field, this.order);
  final String field;
  final String order;
}

Map<String, dynamic> _asMap(dynamic body) =>
    body is Map ? Map<String, dynamic>.from(body) : const {};

List<T> _list<T>(dynamic body, T Function(Map<String, dynamic>) parse) =>
    body is List
    ? body
          .whereType<Map>()
          .map((e) => parse(Map<String, dynamic>.from(e)))
          .toList()
    : <T>[];

/// Reads learners for support. Writes are limited to what a plain admin may do
/// from a phone: switch one account on or off, and gift gems. Deleting an
/// account, changing a role, bulk actions and anything that moves money or
/// premium stay on the web admin.
class UsersRepository {
  UsersRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  /// One page of learners. [filters] may hold `search`, `role` (0-2),
  /// `is_active` (bool) and `sort` ([UserSort]).
  Future<PageResult<AdminUserItem>> listUsers(
    PageRequest request,
    Map<String, Object?> filters,
  ) async {
    final search = (filters['search'] as String?)?.trim();
    final sort = filters['sort'] as UserSort? ?? UserSort.newest;
    final data = _asMap(
      await _api.getData(
        ApiEndpoints.adminUsers,
        params: {
          'page': request.page,
          'page_size': request.size,
          if (search != null && search.isNotEmpty) 'search': search,
          if (filters['role'] != null) 'role': filters['role'],
          if (filters['is_active'] != null) 'is_active': filters['is_active'],
          'sort_by': sort.field,
          'order': sort.order,
        },
      ),
    );
    final total = data['total'];
    final pages = data['total_pages'];
    return PageResult(
      items: _list(data['users'], AdminUserItem.fromJson),
      total: total is num ? total.toInt() : null,
      hasMore: pages is num ? request.page < pages.toInt() : null,
    );
  }

  Future<AdminUserDetail> getUser(String id) async => AdminUserDetail.fromJson(
    _asMap(await _api.getData('${ApiEndpoints.adminUsers}/$id')),
  );

  Future<List<UserActivityEntry>> getActivity(
    String id, {
    int days = 30,
  }) async => _list(
    await _api.getData(
      '${ApiEndpoints.adminUsers}/$id/activity',
      params: {'days': days},
    ),
    UserActivityEntry.fromJson,
  );

  Future<WalletPage> getWallet(String id, PageRequest request) async =>
      WalletPage.fromJson(
        _asMap(
          await _api.getData(
            '${ApiEndpoints.adminUsers}/$id/wallet',
            params: {'limit': request.limit, 'offset': request.offset},
          ),
        ),
      );

  Future<XpPage> getXp(String id, PageRequest request) async => XpPage.fromJson(
    _asMap(
      await _api.getData(
        '${ApiEndpoints.adminUsers}/$id/xp-transactions',
        params: {'limit': request.limit, 'offset': request.offset},
      ),
    ),
  );

  Future<List<InventoryEntry>> getInventory(String id) async => _list(
    _asMap(
      await _api.getData('${ApiEndpoints.adminUsers}/$id/inventory'),
    )['items'],
    InventoryEntry.fromJson,
  );

  Future<PremiumStatus> getPremium(String id) async => PremiumStatus.fromJson(
    _asMap(await _api.getData('${ApiEndpoints.adminUsers}/$id/entitlements')),
  );

  Future<void> setActive(String id, bool isActive) => _api.put(
    '${ApiEndpoints.adminUsers}/$id/status',
    data: {'is_active': isActive},
  );

  /// Gems only; course, avatar and item gifts stay on the web admin. The
  /// backend checks the per-action cap and today's budget.
  Future<void> giftGems(
    String id, {
    required int amount,
    required String reason,
  }) => _api.post(
    '${ApiEndpoints.adminUsers}/$id/gift',
    data: {'gift_type': 'gems', 'amount': amount, 'reason': reason},
  );
}
