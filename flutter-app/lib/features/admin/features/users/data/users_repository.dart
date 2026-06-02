import '../../../core/network/api_client.dart';

class AdminUserItem {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String status;
  final String level;
  final String roleSlug;
  final int totalXp;
  final int numericLevel;
  final String rank;

  const AdminUserItem({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    required this.status,
    required this.level,
    required this.roleSlug,
    required this.totalXp,
    required this.numericLevel,
    required this.rank,
  });

  factory AdminUserItem.fromJson(Map<String, dynamic> j) => AdminUserItem(
        id: j['id']?.toString() ?? '',
        email: j['email'] ?? '',
        displayName: j['display_name'] ?? j['username'] ?? '',
        avatarUrl: j['avatar_url'],
        status: j['is_active'] == true ? 'active' : 'inactive',
        level: j['cefr_level'] ?? j['level'] ?? 'A1',
        roleSlug: j['role_slug'] ?? 'user',
        totalXp: j['total_xp'] ?? 0,
        numericLevel: j['numeric_level'] ?? 1,
        rank: j['rank'] ?? 'bronze',
      );

  String get statusDisplay {
    switch (status.toLowerCase()) {
      case 'active':
        return 'ACTIVE';
      case 'inactive':
        return 'IDLE';
      case 'blocked':
        return 'BLOCKED';
      default:
        return status.toUpperCase();
    }
  }
}

class UsersRepository {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> getUsers({
    int page = 1,
    String? search,
    String? status,
  }) async {
    final resp = await _api.get('/admin/users', params: {
      'page': page,
      'page_size': 20,
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null) 'status': status,
    });
    final data = resp['data'] as Map<String, dynamic>?;
    return {
      'users': ((data?['users'] as List?) ?? [])
          .map((e) => AdminUserItem.fromJson(e))
          .toList(),
      'total': data?['total'] ?? 0,
    };
  }

  Future<Map<String, dynamic>> getUserStats(String userId) async {
    final resp = await _api.get('/admin/users/$userId');
    return resp['data'] as Map<String, dynamic>? ?? {};
  }

  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    await _api.put('/admin/users/$userId', data: data);
  }

  Future<void> blockUser(String userId) async {
    await _api.put('/admin/users/$userId/status', data: {'is_active': false});
  }

  Future<void> unblockUser(String userId) async {
    await _api.put('/admin/users/$userId/status', data: {'is_active': true});
  }
}
