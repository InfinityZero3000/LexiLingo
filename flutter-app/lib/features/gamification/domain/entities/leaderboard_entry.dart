import 'package:equatable/equatable.dart';

/// Leaderboard Entry Entity
class LeaderboardEntryEntity extends Equatable {
  final int rank;
  final String odUserId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int xpEarned;
  final int lessonsCompleted;
  final bool isCurrentUser;

  const LeaderboardEntryEntity({
    required this.rank,
    required this.odUserId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.xpEarned,
    this.lessonsCompleted = 0,
    this.isCurrentUser = false,
  });

  factory LeaderboardEntryEntity.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntryEntity(
      rank: json['rank'] ?? 0,
      odUserId: json['user_id'] ?? json['userId'] ?? '',
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? json['displayName'] ?? '',
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
      xpEarned: json['xp_earned'] ?? json['xpEarned'] ?? 0,
      lessonsCompleted: json['lessons_completed'] ?? json['lessonsCompleted'] ?? 0,
      isCurrentUser: json['is_current_user'] ?? json['isCurrentUser'] ?? false,
    );
  }

  @override
  List<Object?> get props => [rank, odUserId, xpEarned];
}

/// League Status Entity
class LeagueStatusEntity extends Equatable {
  final String league;
  final int currentRank;
  final int xpEarned;
  final int lessonsCompleted;
  final bool isInPromotionZone;
  final bool isInDemotionZone;
  final int weekEndsInHours;

  const LeagueStatusEntity({
    required this.league,
    required this.currentRank,
    required this.xpEarned,
    this.lessonsCompleted = 0,
    this.isInPromotionZone = false,
    this.isInDemotionZone = false,
    this.weekEndsInHours = 0,
  });

  /// League types
  static const String bronze = 'bronze';
  static const String silver = 'silver';
  static const String gold = 'gold';
  static const String platinum = 'platinum';
  static const String diamond = 'diamond';

  static const List<String> leagueOrder = [bronze, silver, gold, platinum, diamond];

  String get nextLeague {
    final index = leagueOrder.indexOf(league);
    if (index < leagueOrder.length - 1) {
      return leagueOrder[index + 1];
    }
    return league; // Already at top
  }

  bool get isTopLeague => league == diamond;

  factory LeagueStatusEntity.fromJson(Map<String, dynamic> json) {
    return LeagueStatusEntity(
      league: json['league'] ?? bronze,
      currentRank: json['current_rank'] ?? json['currentRank'] ?? 0,
      xpEarned: json['xp_earned'] ?? json['xpEarned'] ?? 0,
      lessonsCompleted: json['lessons_completed'] ?? json['lessonsCompleted'] ?? 0,
      isInPromotionZone: json['is_in_promotion_zone'] ?? json['isInPromotionZone'] ?? false,
      isInDemotionZone: json['is_in_demotion_zone'] ?? json['isInDemotionZone'] ?? false,
      weekEndsInHours: json['week_ends_in_hours'] ?? json['weekEndsInHours'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [league, currentRank, xpEarned];
}

/// Leaderboard Response Entity
class LeaderboardEntity extends Equatable {
  final String league;
  final DateTime weekStart;
  final DateTime weekEnd;
  final List<LeaderboardEntryEntity> entries;
  final int? currentUserRank;
  final int totalParticipants;

  const LeaderboardEntity({
    required this.league,
    required this.weekStart,
    required this.weekEnd,
    required this.entries,
    this.currentUserRank,
    this.totalParticipants = 0,
  });

  List<LeaderboardEntryEntity> get topThree =>
      entries.take(3).toList();

  factory LeaderboardEntity.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntity(
      league: json['league'] ?? 'bronze',
      weekStart: DateTime.parse(json['week_start'] ?? json['weekStart']),
      weekEnd: DateTime.parse(json['week_end'] ?? json['weekEnd']),
      entries: (json['entries'] as List? ?? [])
          .map((e) => LeaderboardEntryEntity.fromJson(e))
          .toList(),
      currentUserRank: json['current_user_rank'] ?? json['currentUserRank'],
      totalParticipants: json['total_participants'] ?? json['totalParticipants'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [league, weekStart, entries.length];
}
