import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';

/// User model matching backend Phase 1 API response
/// From backend-service/app/models/user.py
class UserModel extends UserEntity {
  UserModel({
    required super.id,
    required super.email,
    required super.username,
    required super.displayName,
    super.avatarUrl,
    super.provider,
    super.isVerified,
    super.isOnboardingCompleted,
    super.roleSlug,
    super.cefrLevel,
    super.certifiedLevel,
    super.levelVerified,
    super.nativeLanguage,
    super.lexiReplyLanguage,
    super.totalXp,
    super.numericLevel,
    super.currentStreak,
    super.lessonsCompleted,
    super.lastLogin,
    super.lastLoginIp,
    required super.createdAt,
    super.updatedAt,
  });

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    if (value != null) {
      final normalized = value.toString();
      if (normalized.isNotEmpty && normalized != 'null') {
        return normalized;
      }
    }
    throw FormatException('Missing or invalid "$key" in user response');
  }

  static String? _optionalString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is List && value.isNotEmpty) {
      return value.first.toString();
    }
    final normalized = value.toString();
    return normalized == 'null' ? null : normalized;
  }

  /// Convert from backend API JSON response
  factory UserModel.fromJson(Map<String, dynamic> json) {
    final parsedCreatedAt = _optionalString(json['created_at']);
    final parsedUpdatedAt = _optionalString(json['updated_at']);
    final parsedLastLogin = _optionalString(json['last_login']);

    return UserModel(
      id: _requiredString(json, 'id'),
      email: _requiredString(json, 'email'),
      username: _requiredString(json, 'username'),
      displayName:
          _optionalString(json['display_name']) ??
          _requiredString(json, 'username'),
      avatarUrl: _optionalString(json['avatar_url']),
      provider: _optionalString(json['provider']) ?? 'local',
      isVerified: json['is_verified'] as bool? ?? false,
      isOnboardingCompleted: json['is_onboarding_completed'] as bool? ?? false,
      roleSlug:
          _optionalString(json['role_slug']) ??
          _optionalString(json['role']) ??
          'user',
      cefrLevel: _optionalString(json['cefr_level']) ?? 'A1',
      certifiedLevel: _optionalString(json['certified_level']) ?? 'A1',
      levelVerified: json['level_verified'] as bool? ?? true,
      nativeLanguage: _optionalString(json['native_language']) ?? 'vi',
      lexiReplyLanguage:
          json['lexi_reply_language'] == UserEntity.lexiReplyNative
          ? UserEntity.lexiReplyNative
          : UserEntity.lexiReplyApp,
      totalXp: json['total_xp'] as int? ?? 0,
      numericLevel: json['numeric_level'] as int? ?? 1,
      currentStreak: json['current_streak'] as int? ?? 0,
      lessonsCompleted: json['lessons_completed'] as int?,
      lastLogin: parsedLastLogin != null
          ? DateTime.tryParse(parsedLastLogin)
          : null,
      lastLoginIp: _optionalString(json['last_login_ip']),
      createdAt: parsedCreatedAt != null
          ? DateTime.tryParse(parsedCreatedAt) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: parsedUpdatedAt != null
          ? DateTime.tryParse(parsedUpdatedAt)
          : null,
    );
  }

  /// Convert to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'provider': provider,
      'is_verified': isVerified,
      'is_onboarding_completed': isOnboardingCompleted,
      'role_slug': roleSlug,
      'cefr_level': cefrLevel,
      'level': cefrLevel,
      'certified_level': certifiedLevel,
      'level_verified': levelVerified,
      'native_language': nativeLanguage,
      'lexi_reply_language': lexiReplyLanguage,
      'total_xp': totalXp,
      'numeric_level': numericLevel,
      'current_streak': currentStreak,
      'lessons_completed': lessonsCompleted,
      'last_login': lastLogin?.toIso8601String(),
      'last_login_ip': lastLoginIp,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Convert from Entity to Model
  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      email: entity.email,
      username: entity.username,
      displayName: entity.displayName,
      avatarUrl: entity.avatarUrl,
      provider: entity.provider,
      isVerified: entity.isVerified,
      isOnboardingCompleted: entity.isOnboardingCompleted,
      roleSlug: entity.roleSlug,
      cefrLevel: entity.cefrLevel,
      certifiedLevel: entity.certifiedLevel,
      levelVerified: entity.levelVerified,
      nativeLanguage: entity.nativeLanguage,
      lexiReplyLanguage: entity.lexiReplyLanguage,
      totalXp: entity.totalXp,
      numericLevel: entity.numericLevel,
      currentStreak: entity.currentStreak,
      lessonsCompleted: entity.lessonsCompleted,
      lastLogin: entity.lastLogin,
      lastLoginIp: entity.lastLoginIp,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}
