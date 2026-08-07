import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';

class AdminUserItem {
  final String id, email, displayName, roleSlug, level, rank;
  final String? avatarUrl, createdAt, lastLogin;
  final bool isActive, isVerified;
  final int roleLevel, totalXp, numericLevel, streakDays;

  const AdminUserItem({
    required this.id,
    required this.email,
    required this.displayName,
    required this.roleSlug,
    required this.level,
    required this.rank,
    this.avatarUrl,
    this.createdAt,
    this.lastLogin,
    required this.isActive,
    required this.isVerified,
    required this.roleLevel,
    required this.totalXp,
    required this.numericLevel,
    required this.streakDays,
  });

  factory AdminUserItem.fromJson(Map<String, dynamic> json) => AdminUserItem(
        id: json['id']?.toString() ?? '',
        email: json['email'] ?? '',
        displayName: json['display_name'] ?? json['username'] ?? '',
        avatarUrl: json['avatar_url'],
        isActive: json['is_active'] == true,
        isVerified: json['is_verified'] == true,
        roleSlug: json['role_slug'] ?? 'user',
        roleLevel: json['role_level'] ?? 0,
        totalXp: json['total_xp'] ?? 0,
        numericLevel: json['numeric_level'] ?? 1,
        rank: json['rank'] ?? 'bronze',
        level: json['cefr_level'] ?? 'A1',
        streakDays: json['streak_days'] ?? 0,
        createdAt: json['created_at']?.toString(),
        lastLogin: json['last_login']?.toString(),
      );

  String get roleLabel => const ['User', 'Admin', 'Super Admin'][roleLevel.clamp(0, 2)];
}

class UsersRepository {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> getUsers({
    int page = 1,
    String? search,
    int? role,
    bool? isActive,
  }) async {
    final response = await _api.get(ApiEndpoints.adminUsers, params: {
      'page': page,
      'page_size': 20,
      if (search?.isNotEmpty == true) 'search': search,
      if (role != null) 'role': role,
      if (isActive != null) 'is_active': isActive,
    });
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return {
      'users': ((data['users'] as List?) ?? [])
          .map((item) => AdminUserItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      'total': data['total'] ?? 0,
      'total_pages': data['total_pages'] ?? 1,
    };
  }

  Future<Map<String, dynamic>> getUserStats(String userId) async {
    final response = await _api.get('${ApiEndpoints.adminUsers}/$userId');
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<List<Map<String, dynamic>>> getUserActivity(String userId) async {
    final response = await _api.get('${ApiEndpoints.adminUsers}/$userId/activity');
    return ((response['data'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> updateUser(String userId, Map<String, dynamic> data) =>
      _api.put('${ApiEndpoints.adminUsers}/$userId', data: data);

  Future<void> updateRole(String userId, int level) =>
      _api.put('${ApiEndpoints.adminUsers}/$userId/role', data: {'level': level});

  Future<void> setUserActive(String userId, bool isActive) => _api.put(
        '${ApiEndpoints.adminUsers}/$userId/status',
        data: {'is_active': isActive},
      );

  Future<void> bulkAction(Iterable<String> userIds, String action) => _api.post(
        '${ApiEndpoints.adminUsers}/bulk-action',
        data: {'user_ids': userIds.toList(), 'action': action},
      );
}
