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
  final _api = ApiClient.instance;

  Future<void> requestOtp(String email) async {
    await _api.post(ApiEndpoints.adminRequestOtp, data: {'email': email});
  }

  Future<AdminUser> verifyOtp(String email, String otp) async {
    final resp = await _api.post(
      ApiEndpoints.adminVerifyOtp,
      data: {'email': email, 'otp': otp},
    );

    return _persistAdminSession(_unwrapData(resp), fallbackEmail: email);
  }

  Future<AdminUser> loginWithGoogle(String idToken) async {
    final resp = await _api.post(
      ApiEndpoints.googleLogin,
      data: {'id_token': idToken, 'source': 'admin'},
    );
    final data = _unwrapData(resp);
    final email = (data['user'] as Map?)?['email']?.toString() ??
        data['email']?.toString() ??
        '';
    return _persistAdminSession(data, fallbackEmail: email);
  }

  Future<AdminUser?> getMe() async {
    try {
      final json = await TokenStorage.getUser();
      if (json != null) {
        final fresh = await _api.get(ApiEndpoints.me);
        final userJson = _unwrapData(fresh);
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
      await _api.post(
        ApiEndpoints.logout,
        data: {'refresh_token': await TokenStorage.getRefreshToken() ?? ''},
      );
    } catch (_) {}
    await TokenStorage.clear();
  }

  Future<AdminUser> _persistAdminSession(
    Map<String, dynamic> data, {
    required String fallbackEmail,
  }) async {
    final accessToken = data['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Missing access token');
    }

    await TokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: data['refresh_token']?.toString() ?? '',
    );

    final userJson =
        _asStringKeyMap(data['user']) ??
        _userFromFlatLogin(data, fallbackEmail: fallbackEmail);

    final user = AdminUser.fromJson(userJson);
    await TokenStorage.saveUser(jsonEncode(userJson));
    return user;
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic> resp) {
    return _asStringKeyMap(resp['data']) ?? resp;
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Map<String, dynamic> _userFromFlatLogin(
    Map<String, dynamic> data, {
    required String fallbackEmail,
  }) {
    final roleSlug = (data['role'] ?? data['role_slug'] ?? 'user')
        .toString()
        .toLowerCase();
    final roleLevel = _roleLevel(roleSlug);
    final email = (data['email'] ?? fallbackEmail).toString();
    final username = (data['username'] ?? email.split('@').first).toString();

    return {
      'id': data['user_id']?.toString() ?? data['id']?.toString() ?? '',
      'email': email,
      'username': username,
      'display_name': data['display_name']?.toString() ?? username,
      'avatar_url': data['avatar_url'],
      'role_slug': roleSlug,
      'role_level': roleLevel,
      'is_super_admin': roleLevel >= 2,
      'is_admin': roleLevel >= 1,
    };
  }

  int _roleLevel(String roleSlug) {
    if (roleSlug == 'super_admin') return 2;
    if (roleSlug == 'admin') return 1;
    return 0;
  }
}
