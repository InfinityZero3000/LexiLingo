import 'package:flutter/material.dart';

/// Rank tier configuration
class RankTierData {
  final String name;
  final Color color;
  final Color colorDark;
  final IconData icon;

  const RankTierData({
    required this.name,
    required this.color,
    required this.colorDark,
    required this.icon,
  });
}

/// Mapping from rank key → visual data
const Map<String, RankTierData> _rankTiers = {
  'bronze': RankTierData(
    name: 'Bronze',
    color: Color(0xFFCD7F32),
    colorDark: Color(0xFF8B5A2B),
    icon: Icons.shield_outlined,
  ),
  'silver': RankTierData(
    name: 'Silver',
    color: Color(0xFFC0C0C0),
    colorDark: Color(0xFF808080),
    icon: Icons.shield,
  ),
  'gold': RankTierData(
    name: 'Gold',
    color: Color(0xFFFFD700),
    colorDark: Color(0xFFDAA520),
    icon: Icons.military_tech,
  ),
  'platinum': RankTierData(
    name: 'Platinum',
    color: Color(0xFF00CED1),
    colorDark: Color(0xFF008B8B),
    icon: Icons.diamond_outlined,
  ),
  'diamond': RankTierData(
    name: 'Diamond',
    color: Color(0xFF7B68EE),
    colorDark: Color(0xFF483D8B),
    icon: Icons.diamond,
  ),
  'master': RankTierData(
    name: 'Master',
    color: Color(0xFFFF4500),
    colorDark: Color(0xFFB22222),
    icon: Icons.workspace_premium,
  ),
};

RankTierData _getRankData(String rank) {
  return _rankTiers[rank.toLowerCase()] ?? _rankTiers['bronze']!;
}

/// Compact rank badge for profile / header display
class RankBadge extends StatelessWidget {
  final String rank;
  final double size;
  final VoidCallback? onTap;

  const RankBadge({
    super.key,
    required this.rank,
    this.size = 36,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = _getRankData(rank);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [data.color, data.colorDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: data.color.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          data.icon,
          size: size * 0.5,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Labelled rank badge with name below the icon
class RankBadgeLabelled extends StatelessWidget {
  final String rank;
  final double iconSize;
  final VoidCallback? onTap;

  const RankBadgeLabelled({
    super.key,
    required this.rank,
    this.iconSize = 48,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = _getRankData(rank);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RankBadge(rank: rank, size: iconSize, onTap: null),
          const SizedBox(height: 4),
          Text(
            data.name,
            style: TextStyle(
              color: data.color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full rank card for profile pages
class RankCard extends StatelessWidget {
  final String rank;
  final double rankScore;
  final int numericLevel;
  final String proficiencyLevel;
  final VoidCallback? onTap;

  const RankCard({
    super.key,
    required this.rank,
    required this.rankScore,
    required this.numericLevel,
    required this.proficiencyLevel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = _getRankData(rank);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              data.color.withValues(alpha: 0.15),
              data.color.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: data.color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Rank Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [data.color, data.colorDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(data.icon, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: data.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Level $numericLevel · $proficiencyLevel',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            // Score
            Column(
              children: [
                Text(
                  rankScore.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: data.color,
                  ),
                ),
                Text(
                  'Score',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
