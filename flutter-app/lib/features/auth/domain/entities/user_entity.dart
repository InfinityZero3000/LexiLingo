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
  final String roleSlug; // 'user', 'admin', 'super_admin' or a custom role

  /// 0 learner, 1 admin (custom roles included), 2 super admin.
  final int roleLevel;
  final String cefrLevel; // CEFR level: A1, A2, B1, B2, C1, C2

  /// What a test confirmed; rank reads it. [cefrLevel] is the working level
  /// the learner may pick, and is unverified while it sits above this one.
  final String certifiedLevel;
  final bool levelVerified;
  final String nativeLanguage; // ISO code: vi, en, ja, ko, zh, fr, es

  /// Which language Lexi explains in: [lexiReplyApp] follows the UI language,
  /// [lexiReplyNative] uses [nativeLanguage].
  final String lexiReplyLanguage;
  static const lexiReplyApp = 'app';
  static const lexiReplyNative = 'native';
  final int totalXp;
  final int numericLevel;
  final int currentStreak;

  /// Null when the backend did not say, which is not the same as zero.
  final int? lessonsCompleted;
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
    this.roleSlug = 'user',
    this.roleLevel = 0,
    this.cefrLevel = 'A1',
    this.certifiedLevel = 'A1',
    this.levelVerified = true,
    this.nativeLanguage = 'vi',
    this.lexiReplyLanguage = lexiReplyApp,
    this.totalXp = 0,
    this.numericLevel = 1,
    this.currentStreak = 0,
    this.lessonsCompleted,
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
    String? roleSlug,
    int? roleLevel,
    String? cefrLevel,
    String? certifiedLevel,
    bool? levelVerified,
    String? nativeLanguage,
    String? lexiReplyLanguage,
    int? totalXp,
    int? numericLevel,
    int? currentStreak,
    int? lessonsCompleted,
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
      roleSlug: roleSlug ?? this.roleSlug,
      roleLevel: roleLevel ?? this.roleLevel,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      certifiedLevel: certifiedLevel ?? this.certifiedLevel,
      levelVerified: levelVerified ?? this.levelVerified,
      nativeLanguage: nativeLanguage ?? this.nativeLanguage,
      lexiReplyLanguage: lexiReplyLanguage ?? this.lexiReplyLanguage,
      totalXp: totalXp ?? this.totalXp,
      numericLevel: numericLevel ?? this.numericLevel,
      currentStreak: currentStreak ?? this.currentStreak,
      lessonsCompleted: lessonsCompleted ?? this.lessonsCompleted,
      lastLogin: lastLogin ?? this.lastLogin,
      lastLoginIp: lastLoginIp ?? this.lastLoginIp,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// The language Lexi should explain in, given the one the UI shows.
  String lexiReplyLanguageFor(String appLanguage) =>
      lexiReplyLanguage == lexiReplyNative ? nativeLanguage : appLanguage;

  bool get canAccessAdminPanel {
    if (roleLevel >= 1) return true;
    // Responses and cached profiles without a level still name the built-ins.
    final normalizedRole = roleSlug.trim().toLowerCase();
    return normalizedRole == 'admin' || normalizedRole == 'super_admin';
  }
}
