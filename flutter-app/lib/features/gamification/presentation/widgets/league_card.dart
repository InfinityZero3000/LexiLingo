import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';

/// League Card Widget
/// Shows user's current league status
class LeagueCard extends StatelessWidget {
  final LeagueStatusEntity status;
  final VoidCallback? onTap;

  const LeagueCard({
    super.key,
    required this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final leagueData = _getLeagueData(status.league);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              leagueData.color.withValues(alpha: 0.15),
              leagueData.color.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: leagueData.color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // League Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [leagueData.color, leagueData.colorDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: leagueData.color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                leagueData.icon,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),

            // League Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        leagueData.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: leagueData.color,
                        ),
                      ),
                      if (status.isInPromotionZone) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '⬆ PROMOTION',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rank #${status.currentRank} · ${status.xpEarned} XP this week',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
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

            // Arrow
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
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
    switch (league.toLowerCase()) {
      case 'bronze':
        return _LeagueData(
          name: 'Bronze League',
          icon: Icons.shield_outlined,
          color: const Color(0xFFCD7F32),
          colorDark: const Color(0xFFB8720E),
        );
      case 'silver':
        return _LeagueData(
          name: 'Silver League',
          icon: Icons.shield,
          color: const Color(0xFFC0C0C0),
          colorDark: const Color(0xFF9E9E9E),
        );
      case 'gold':
        return _LeagueData(
          name: 'Gold League',
          icon: Icons.emoji_events_outlined,
          color: const Color(0xFFFFD700),
          colorDark: const Color(0xFFE5C100),
        );
      case 'platinum':
        return _LeagueData(
          name: 'Platinum League',
          icon: Icons.emoji_events,
          color: const Color(0xFFE5E4E2),
          colorDark: const Color(0xFFB8B8B6),
        );
      case 'diamond':
        return _LeagueData(
          name: 'Diamond League',
          icon: Icons.diamond,
          color: const Color(0xFFB9F2FF),
          colorDark: const Color(0xFF7DD3EA),
        );
      default:
        return _LeagueData(
          name: 'Bronze League',
          icon: Icons.shield_outlined,
          color: const Color(0xFFCD7F32),
          colorDark: const Color(0xFFB8720E),
        );
    }
  }
}

class _LeagueData {
  final String name;
  final IconData icon;
  final Color color;
  final Color colorDark;

  _LeagueData({
    required this.name,
    required this.icon,
    required this.color,
    required this.colorDark,
  });
}

/// League Badge - Compact version for display
class LeagueBadge extends StatelessWidget {
  final String league;
  final double size;

  const LeagueBadge({
    super.key,
    required this.league,
    this.size = 32,
  });

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
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        data.$3,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }

  (Color, Color, IconData) _getLeagueColor(String league) {
    switch (league.toLowerCase()) {
      case 'bronze':
        return (const Color(0xFFCD7F32), const Color(0xFFB8720E), Icons.shield_outlined);
      case 'silver':
        return (const Color(0xFFC0C0C0), const Color(0xFF9E9E9E), Icons.shield);
      case 'gold':
        return (const Color(0xFFFFD700), const Color(0xFFE5C100), Icons.emoji_events_outlined);
      case 'platinum':
        return (const Color(0xFFE5E4E2), const Color(0xFFB8B8B6), Icons.emoji_events);
      case 'diamond':
        return (const Color(0xFFB9F2FF), const Color(0xFF7DD3EA), Icons.diamond);
      default:
        return (const Color(0xFFCD7F32), const Color(0xFFB8720E), Icons.shield_outlined);
    }
  }
}
