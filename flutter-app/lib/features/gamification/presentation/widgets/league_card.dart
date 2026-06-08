import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_asset_icon.dart';

/// League Card Widget
/// Shows user's current league status, or a selected leaderboard entry's info
class LeagueCard extends StatelessWidget {
  final LeagueStatusEntity status;
  final LeaderboardEntryEntity? selectedEntry;
  final VoidCallback? onTap;

  const LeagueCard({
    super.key,
    required this.status,
    this.selectedEntry,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entry = selectedEntry;
    if (entry != null) {
      return _buildEntryCard(context, entry, isDark);
    }
    return _buildStatusCard(context, isDark);
  }

  Widget _buildStatusCard(BuildContext context, bool isDark) {
    final leagueData = _getLeagueData(status.league);

    return GestureDetector(
      onTap: onTap,
      child: _CardShell(
        color: leagueData.color,
        isDark: isDark,
        child: Row(
          children: [
            RankAssetIcon(
              rank: status.league,
              size: 124,
              iconScale: 1.42,
              iconOffset: const Offset(0, -10),
              paddingRatio: 0,
            ),
            const SizedBox(width: 26),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: status.league == 'master'
                            ? ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        Color(0xFF5AB6FF),
                                        Color(0xFFFFD64F),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ).createShader(bounds),
                                child: Text(
                                  leagueData.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            : Text(
                                leagueData.name,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: leagueData.color,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'gamification.rankWeekly'.tr(
                      namedArgs: {
                        'rank': '${status.currentRank}',
                        'xp': '${status.xpEarned}',
                      },
                    ),
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _RankMetricChip(
                        label: 'Score',
                        value: status.rankScore.toStringAsFixed(0),
                        color: leagueData.color,
                      ),
                      _RankMetricChip(
                        label: status.proficiencyLevel,
                        value: 'Lv ${status.numericLevel}',
                        color: AppColorRoles.primary(isDark),
                      ),
                    ],
                  ),
                  if (status.weekEndsInHours > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTimeRemaining(status.weekEndsInHours),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    LeaderboardEntryEntity entry,
    bool isDark,
  ) {
    final leagueData = _getLeagueData(entry.userRank);
    final primaryColor = AppColorRoles.primary(isDark);
    final rankColor = _getRankPositionColor(entry.rank);

    return GestureDetector(
      onTap: onTap,
      child: _CardShell(
        color: leagueData.color,
        isDark: isDark,
        child: Row(
          children: [
            RankAssetIcon(
              rank: entry.userRank,
              size: 124,
              iconScale: 1.42,
              iconOffset: const Offset(0, -10),
              paddingRatio: 0,
            ),
            const SizedBox(width: 26),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display name
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.displayName.isNotEmpty
                              ? entry.displayName
                              : entry.username,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: entry.isCurrentUser
                                ? primaryColor
                                : (isDark
                                      ? AppColors.textInverted
                                      : AppColors.textDark),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isCurrentUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // League name
                  entry.userRank == 'master'
                      ? ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF5AB6FF), Color(0xFFFFD64F)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: Text(
                            leagueData.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          leagueData.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: leagueData.color,
                          ),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    'gamification.rankWeekly'.tr(
                      namedArgs: {
                        'rank': '${entry.rank}',
                        'xp': '${entry.xpEarned}',
                      },
                    ),
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _RankMetricChip(
                        label: 'Hạng',
                        value: '#${entry.rank}',
                        color: rankColor,
                      ),
                      _RankMetricChip(
                        label: 'Lessons',
                        value: '${entry.lessonsCompleted}',
                        color: leagueData.color,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  String _formatTimeRemaining(int hours) {
    if (hours >= 24) {
      final days = hours ~/ 24;
      return '$days day${days > 1 ? 's' : ''} left';
    }
    return '$hours hour${hours > 1 ? 's' : ''} left';
  }

  _LeagueData _getLeagueData(String league) {
    final data = rankVisualDataFor(league);
    return _LeagueData(
      name: '${rankDisplayNameFor(league)} League',
      color: data.color,
      colorDark: data.colorDark,
    );
  }

  Color _getRankPositionColor(int rank) {
    switch (rank) {
      case 1:
        return AppColors.gold;
      case 2:
        return AppColors.textMuted;
      case 3:
        return AppColors.bronze;
      default:
        return Colors.grey;
    }
  }
}

class _CardShell extends StatelessWidget {
  final Color color;
  final bool isDark;
  final Widget child;

  const _CardShell({
    required this.color,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(
          alpha: isDark ? 0.44 : 0.74,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.15),
              color.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }
}

class _RankMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _RankMetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        '$label · $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _LeagueData {
  final String name;
  final Color color;
  final Color colorDark;

  _LeagueData({
    required this.name,
    required this.color,
    required this.colorDark,
  });
}

/// League Badge - Compact version for display
class LeagueBadge extends StatelessWidget {
  final String league;
  final double size;

  const LeagueBadge({super.key, required this.league, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final data = _getLeagueColor(league);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [data.$1, data.$2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: data.$1.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: RankAssetIcon(rank: league, size: size * 0.78, decorated: false),
    );
  }

  (Color, Color) _getLeagueColor(String league) {
    final data = rankVisualDataFor(league);
    return (data.color, data.colorDark);
  }
}
