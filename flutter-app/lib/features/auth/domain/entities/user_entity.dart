/// User entity matching backend Phase 1 schema
/// From backend-service/app/models/user.py
class UserEntity {
  final String id; // UUID from backend
  final String email;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String provider; // 'local', 'google', 'facebook'
  final bool isVerified;
  final bool isOnboardingCompleted;
  final String cefrLevel; // CEFR level: A1, A2, B1, B2, C1, C2
  final int totalXp;
  final int numericLevel;
  final int currentStreak;
  final DateTime? lastLogin;
  final String? lastLoginIp;
  final DateTime createdAt;
  final DateTime? updatedAt;

  UserEntity({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.provider = 'local',
    this.isVerified = false,
    this.isOnboardingCompleted = false,
    this.cefrLevel = 'A1',
    this.totalXp = 0,
    this.numericLevel = 1,
    this.currentStreak = 0,
    this.lastLogin,
    this.lastLoginIp,
    required this.createdAt,
    this.updatedAt,
  });

  UserEntity copyWith({
    String? id,
    String? email,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? provider,
    bool? isVerified,
    bool? isOnboardingCompleted,
    String? cefrLevel,
    int? totalXp,
    int? numericLevel,
    int? currentStreak,
    DateTime? lastLogin,
    String? lastLoginIp,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      provider: provider ?? this.provider,
      isVerified: isVerified ?? this.isVerified,
      isOnboardingCompleted:
          isOnboardingCompleted ?? this.isOnboardingCompleted,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      totalXp: totalXp ?? this.totalXp,
      numericLevel: numericLevel ?? this.numericLevel,
      currentStreak: currentStreak ?? this.currentStreak,
      lastLogin: lastLogin ?? this.lastLogin,
      lastLoginIp: lastLoginIp ?? this.lastLoginIp,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
