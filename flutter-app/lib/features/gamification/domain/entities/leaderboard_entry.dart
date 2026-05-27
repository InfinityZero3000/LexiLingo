import 'package:equatable/equatable.dart';

/// Leaderboard Entry Entity
class LeaderboardEntryEntity extends Equatable {
  final int rank;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String userRank;
  final int xpEarned;
  final int lessonsCompleted;
  final bool isCurrentUser;

  const LeaderboardEntryEntity({
    required this.rank,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.userRank = 'bronze',
    required this.xpEarned,
    this.lessonsCompleted = 0,
    this.isCurrentUser = false,
  });

  factory LeaderboardEntryEntity.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntryEntity(
      rank: json['rank'] ?? 0,
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      username: json['username'] ?? '',
      displayName:
          (json['display_name'] ??
                  json['displayName'] ??
                  json['username'] ??
                  '')
              .toString(),
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
      userRank: (json['user_rank'] ?? json['userRank'] ?? 'bronze').toString(),
      xpEarned: json['xp_earned'] ?? json['xpEarned'] ?? 0,
      lessonsCompleted:
          json['lessons_completed'] ?? json['lessonsCompleted'] ?? 0,
      isCurrentUser: json['is_current_user'] ?? json['isCurrentUser'] ?? false,
    );
  }

  @override
  List<Object?> get props => [rank, userId, userRank, xpEarned];
}

/// League Status Entity
class LeagueStatusEntity extends Equatable {
  final String league;
  final String rankName;
  final double rankScore;
  final double rankLevelScore;
  final double rankProficiencyScore;
  final int totalXp;
  final int numericLevel;
  final String proficiencyLevel;
  final int currentRank;
  final int xpEarned;
  final int lessonsCompleted;
  final bool isInPromotionZone;
  final bool isInDemotionZone;
  final int weekEndsInHours;

  const LeagueStatusEntity({
    required this.league,
    this.rankName = 'Bronze',
    this.rankScore = 0,
    this.rankLevelScore = 0,
    this.rankProficiencyScore = 0,
    this.totalXp = 0,
    this.numericLevel = 1,
    this.proficiencyLevel = 'A1',
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
  static const String sapphire = 'sapphire';
  static const String ruby = 'ruby';
  static const String amethyst = 'amethyst';
  static const String master = 'master';

  static const List<String> leagueOrder = [
    bronze,
    silver,
    gold,
    platinum,
    sapphire,
    ruby,
    amethyst,
    master,
  ];

  String get nextLeague {
    final index = leagueOrder.indexOf(league);
    if (index < leagueOrder.length - 1) {
      return leagueOrder[index + 1];
    }
    return league; // Already at top
  }

  bool get isTopLeague => league == master;

  factory LeagueStatusEntity.fromJson(Map<String, dynamic> json) {
    return LeagueStatusEntity(
      league: json['league'] ?? bronze,
      rankName: (json['rank_name'] ?? json['rankName'] ?? 'Bronze').toString(),
      rankScore: (json['rank_score'] ?? json['rankScore'] ?? 0).toDouble(),
      rankLevelScore: (json['rank_level_score'] ?? json['rankLevelScore'] ?? 0)
          .toDouble(),
      rankProficiencyScore:
          (json['rank_proficiency_score'] ?? json['rankProficiencyScore'] ?? 0)
              .toDouble(),
      totalXp: json['total_xp'] ?? json['totalXp'] ?? 0,
      numericLevel: json['numeric_level'] ?? json['numericLevel'] ?? 1,
      proficiencyLevel:
          (json['proficiency_level'] ?? json['proficiencyLevel'] ?? 'A1')
              .toString(),
      currentRank: json['current_rank'] ?? json['currentRank'] ?? 0,
      xpEarned: json['xp_earned'] ?? json['xpEarned'] ?? 0,
      lessonsCompleted:
          json['lessons_completed'] ?? json['lessonsCompleted'] ?? 0,
      isInPromotionZone:
          json['is_in_promotion_zone'] ?? json['isInPromotionZone'] ?? false,
      isInDemotionZone:
          json['is_in_demotion_zone'] ?? json['isInDemotionZone'] ?? false,
      weekEndsInHours:
          json['week_ends_in_hours'] ?? json['weekEndsInHours'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    league,
    currentRank,
    xpEarned,
    rankScore,
    numericLevel,
    proficiencyLevel,
  ];
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

  List<LeaderboardEntryEntity> get topThree => entries.take(3).toList();

  factory LeaderboardEntity.fromJson(Map<String, dynamic> json) {
    DateTime safeParseDate(dynamic raw, DateTime fallback) {
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw) ?? fallback;
      }
      return fallback;
    }

    final now = DateTime.now();
    return LeaderboardEntity(
      league: json['league'] ?? 'bronze',
      weekStart: safeParseDate(json['week_start'] ?? json['weekStart'], now),
      weekEnd: safeParseDate(
        json['week_end'] ?? json['weekEnd'],
        now.add(const Duration(days: 7)),
      ),
      entries: (json['entries'] as List? ?? [])
          .map((e) => LeaderboardEntryEntity.fromJson(e))
          .toList(),
      currentUserRank: json['current_user_rank'] ?? json['currentUserRank'],
      totalParticipants:
          json['total_participants'] ?? json['totalParticipants'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [league, weekStart, entries.length];
}
