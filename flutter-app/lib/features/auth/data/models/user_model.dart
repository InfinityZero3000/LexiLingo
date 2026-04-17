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
    super.level,
    super.xp,
    super.currentStreak,
    super.lastLogin,
    super.lastLoginIp,
    required super.createdAt,
    super.updatedAt,
  });

  /// Convert from backend API JSON response
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      provider: json['provider'] as String? ?? 'local',
      isVerified: json['is_verified'] as bool? ?? false,
      isOnboardingCompleted: json['is_onboarding_completed'] as bool? ?? false,
      level: json['level'] as String? ?? 'A1',
      xp: json['xp'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      lastLogin: json['last_login'] != null
          ? DateTime.parse(json['last_login'] as String)
          : null,
      lastLoginIp: json['last_login_ip'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
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
      'level': level,
      'xp': xp,
      'current_streak': currentStreak,
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
      level: entity.level,
      xp: entity.xp,
      currentStreak: entity.currentStreak,
      lastLogin: entity.lastLogin,
      lastLoginIp: entity.lastLoginIp,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}
