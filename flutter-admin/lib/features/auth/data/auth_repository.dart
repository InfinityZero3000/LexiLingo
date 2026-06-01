import 'dart:convert';
import '../../../core/network/api_client.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/storage/token_storage.dart';

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

  // Accounts that also have a learner profile in the user app.
  static const _userZoneWhitelist = [
    'nhthang312@gmail.com',
    'thefirestar312@gmail.com',
  ];

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

  bool get hasUserZoneAccess =>
      _userZoneWhitelist.contains(email.toLowerCase());

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] ?? '',
        email: json['email'] ?? '',
        displayName: json['display_name'] ?? json['username'] ?? '',
        avatarUrl: json['avatar_url'],
        roleSlug: json['role_slug'] ?? 'admin',
        roleLevel: json['role_level'] ?? 1,
        isSuperAdmin: json['is_super_admin'] ?? false,
        isAdmin: json['is_admin'] ?? true,
        hasUserAccount: true,
      );

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
  final _api = ApiClient.instance;

  Future<void> requestOtp(String email) async {
    await _api.post(
      ApiEndpoints.adminRequestOtp,
      data: {'email': email},
    );
  }

  Future<AdminUser> verifyOtp(String email, String otp) async {
    final resp = await _api.post(
      ApiEndpoints.adminVerifyOtp,
      data: {'email': email, 'otp': otp},
    );

    final data = resp['data'] as Map<String, dynamic>;
    await TokenStorage.saveTokens(
      accessToken: data['access_token'],
      refreshToken: data['refresh_token'] ?? '',
    );

    final userJson = data['user'] as Map<String, dynamic>;
    final user = AdminUser.fromJson(userJson);
    await TokenStorage.saveUser(jsonEncode(userJson));
    return user;
  }

  Future<AdminUser?> getMe() async {
    try {
      final json = await TokenStorage.getUser();
      if (json != null) {
        final fresh = await _api.get(ApiEndpoints.me);
        final userJson = fresh['data'] as Map<String, dynamic>;
        await TokenStorage.saveUser(jsonEncode(userJson));
        return AdminUser.fromJson(userJson);
      }
    } catch (_) {
      final json = await TokenStorage.getUser();
      if (json != null) {
        return AdminUser.fromJson(jsonDecode(json));
      }
    }
    return null;
  }

  Future<void> logout() async {
    try {
      await _api.post(ApiEndpoints.logout, data: {
        'refresh_token': await TokenStorage.getRefreshToken() ?? '',
      });
    } catch (_) {}
    await TokenStorage.clear();
  }
}
