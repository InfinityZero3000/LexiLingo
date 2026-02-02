import 'package:equatable/equatable.dart';

/// User Social Profile Entity
class UserSocialProfileEntity extends Equatable {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isFollowing;
  final int xp;
  final String? league;
  final int currentStreak;

  const UserSocialProfileEntity({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.isFollowing = false,
    this.xp = 0,
    this.league,
    this.currentStreak = 0,
  });

  factory UserSocialProfileEntity.fromJson(Map<String, dynamic> json) {
    return UserSocialProfileEntity(
      userId: json['user_id'] ?? json['userId'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['displayName'] ?? '',
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
      isFollowing: json['is_following'] ?? json['isFollowing'] ?? false,
      xp: json['xp'] ?? 0,
      league: json['league'],
      currentStreak: json['current_streak'] ?? json['currentStreak'] ?? 0,
    );
  }

  UserSocialProfileEntity copyWith({
    String? userId,
    String? username,
    String? displayName,
    String? avatarUrl,
    bool? isFollowing,
    int? xp,
    String? league,
    int? currentStreak,
  }) {
    return UserSocialProfileEntity(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isFollowing: isFollowing ?? this.isFollowing,
      xp: xp ?? this.xp,
      league: league ?? this.league,
      currentStreak: currentStreak ?? this.currentStreak,
    );
  }

  @override
  List<Object?> get props => [userId, username, isFollowing];
}

/// Activity Feed Item Entity
class ActivityFeedItemEntity extends Equatable {
  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String activityType;
  final String message;
  final Map<String, dynamic>? activityData;
  final DateTime createdAt;

  const ActivityFeedItemEntity({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.activityType,
    required this.message,
    this.activityData,
    required this.createdAt,
  });

  /// Activity types
  static const String typeAchievement = 'achievement';
  static const String typeCourse = 'course_completed';
  static const String typeLesson = 'lesson_completed';
  static const String typeStreak = 'streak_milestone';
  static const String typeLevel = 'level_up';

  IconType get iconType {
    switch (activityType) {
      case typeAchievement:
        return IconType.achievement;
      case typeCourse:
        return IconType.course;
      case typeLesson:
        return IconType.lesson;
      case typeStreak:
        return IconType.streak;
      case typeLevel:
        return IconType.level;
      default:
        return IconType.general;
    }
  }

  factory ActivityFeedItemEntity.fromJson(Map<String, dynamic> json) {
    return ActivityFeedItemEntity(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? json['userId'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['displayName'] ?? '',
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
      activityType: json['activity_type'] ?? json['activityType'] ?? 'general',
      message: json['message'] ?? '',
      activityData: json['activity_data'] ?? json['activityData'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, userId, activityType, createdAt];
}

enum IconType {
  achievement,
  course,
  lesson,
  streak,
  level,
  general,
}
