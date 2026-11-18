import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/admin_session_store.dart';

class AdminUser {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String roleSlug;
  final int roleLevel;
  final bool isSuperAdmin;
  final bool isAdmin;
  final bool hasUserAccount;

  const AdminUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    required this.roleSlug,
    required this.roleLevel,
    required this.isSuperAdmin,
    required this.isAdmin,
    required this.hasUserAccount,
  });

  /// The panel is opened from inside the learner app, so every admin signed in
  /// here has a learner account to go back to.
  bool get hasUserZoneAccess => hasUserAccount;

  /// Whether the account may use the panel at all.
  bool get mayUsePanel => isAdmin || isSuperAdmin;

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    final roleSlug = (json['role_slug'] ?? json['role'] ?? 'admin').toString();
    final roleLevel = _roleLevelFromJson(json, roleSlug);

    return AdminUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName:
          json['display_name']?.toString() ??
          json['username']?.toString() ??
          '',
      avatarUrl: json['avatar_url']?.toString(),
      roleSlug: roleSlug,
      roleLevel: roleLevel,
      isSuperAdmin: json['is_super_admin'] == true || roleLevel >= 2,
      isAdmin: json['is_admin'] == true || roleLevel >= 1,
      hasUserAccount: true,
    );
  }

  static int _roleLevelFromJson(Map<String, dynamic> json, String roleSlug) {
    final raw = json['role_level'];
    if (raw is int) return raw;
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null) return parsed;

    final normalizedRole = roleSlug.toLowerCase();
    if (normalizedRole == 'super_admin') return 2;
    if (normalizedRole == 'admin') return 1;
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'role_slug': roleSlug,
    'role_level': roleLevel,
    'is_super_admin': isSuperAdmin,
    'is_admin': isAdmin,
  };
}

class AuthRepository {
  AuthRepository({ApiClient? api, AdminSessionStore? store})
    : _api = api ?? ApiClient.instance,
      _store = store ?? const LearnerSessionStore();

  final ApiClient _api;
  final AdminSessionStore _store;

  /// The signed-in learner as the panel sees them, or null when there is no
  /// session (nothing stored, or the server rejected it). Other failures
  /// throw, so the caller can offer a retry.
  Future<AdminUser?> getMe() async {
    final token = await _store.accessToken();
    if (token == null || token.isEmpty) return null;
    try {
      final resp = await _api.get(ApiEndpoints.me);
      return AdminUser.fromJson(_asStringKeyMap(resp['data']) ?? resp);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      rethrow;
    }
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
