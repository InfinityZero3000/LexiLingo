import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';

/// Leaderboard Podium Widget
/// Displays the top 3 users on a podium
class LeaderboardPodium extends StatelessWidget {
  final List<LeaderboardEntryEntity> topThree;
  
  const LeaderboardPodium({
    super.key,
    required this.topThree,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure we have at least placeholder data for 3 positions
    final first = topThree.isNotEmpty ? topThree[0] : null;
    final second = topThree.length > 1 ? topThree[1] : null;
    final third = topThree.length > 2 ? topThree[2] : null;

    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd Place
          Expanded(
            child: _buildPodiumItem(
              context,
              entry: second,
              rank: 2,
              podiumHeight: 100,
              color: const Color(0xFFC0C0C0),
              medalColor: const Color(0xFFC0C0C0),
            ),
          ),
          const SizedBox(width: 8),
          
          // 1st Place
          Expanded(
            child: _buildPodiumItem(
              context,
              entry: first,
              rank: 1,
              podiumHeight: 130,
              color: const Color(0xFFFFD700),
              medalColor: const Color(0xFFFFD700),
              showCrown: true,
            ),
          ),
          const SizedBox(width: 8),
          
          // 3rd Place
          Expanded(
            child: _buildPodiumItem(
              context,
              entry: third,
              rank: 3,
              podiumHeight: 80,
              color: const Color(0xFFCD7F32),
              medalColor: const Color(0xFFCD7F32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(
    BuildContext context, {
    required LeaderboardEntryEntity? entry,
    required int rank,
    required double podiumHeight,
    required Color color,
    required Color medalColor,
    bool showCrown = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Crown for 1st place
        if (showCrown && entry != null)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            child: const Icon(
              Icons.emoji_events,
              color: Color(0xFFFFD700),
              size: 28,
            ),
          ),
        
        // Avatar with medal
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Avatar
            Container(
              width: rank == 1 ? 60 : 50,
              height: rank == 1 ? 60 : 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color,
                  width: 3,
                ),
                color: entry != null
                    ? (entry.isCurrentUser ? const Color(0xFF137FEC).withValues(alpha: 0.2) : Colors.grey[200])
                    : Colors.grey[200],
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: entry != null
                  ? (entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            entry.avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildInitialAvatar(entry),
                          ),
                        )
                      : _buildInitialAvatar(entry))
                  : Icon(
                      Icons.person_outline,
                      color: Colors.grey[400],
                      size: 24,
                    ),
            ),
            
            // Medal badge
            Positioned(
              bottom: -8,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: medalColor,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Username
        Text(
          entry?.displayName ?? '---',
          style: TextStyle(
            fontSize: 12,
            fontWeight: entry?.isCurrentUser == true ? FontWeight.bold : FontWeight.w500,
            color: entry?.isCurrentUser == true ? const Color(0xFF137FEC) : Colors.grey[800],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        
        // XP
        if (entry != null)
          Text(
            '${entry.xpEarned} XP',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        
        const SizedBox(height: 8),
        
        // Podium
        Container(
          height: podiumHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color,
                color.withValues(alpha: 0.7),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(8),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              _getRankIcon(rank),
              size: 24,
              color: _getRankColor(rank),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialAvatar(LeaderboardEntryEntity entry) {
    return Center(
      child: Text(
        entry.displayName.isNotEmpty
            ? entry.displayName[0].toUpperCase()
            : entry.username[0].toUpperCase(),
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: entry.isCurrentUser ? const Color(0xFF137FEC) : Colors.grey[600],
        ),
      ),
    );
  }

  IconData _getRankIcon(int rank) {
    switch (rank) {
      case 1:
      case 2:
      case 3:
        return Icons.workspace_premium;
      default:
        return Icons.circle;
    }
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return Colors.grey;
    }
  }
}

/// Leaderboard Entry Row Widget
class LeaderboardEntryRow extends StatelessWidget {
  final LeaderboardEntryEntity entry;
  final VoidCallback? onTap;

  const LeaderboardEntryRow({
    super.key,
    required this.entry,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: entry.isCurrentUser
              ? const Color(0xFF137FEC).withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 40,
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _getRankColor(entry.rank),
                ),
              ),
            ),
            
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: entry.isCurrentUser
                    ? const Color(0xFF137FEC).withValues(alpha: 0.2)
                    : Colors.grey[200],
                border: entry.isCurrentUser
                    ? Border.all(color: const Color(0xFF137FEC), width: 2)
                    : null,
              ),
              child: entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        entry.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildInitial(),
                      ),
                    )
                  : _buildInitial(),
            ),
            const SizedBox(width: 12),
            
            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: entry.isCurrentUser
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: entry.isCurrentUser
                                ? const Color(0xFF137FEC)
                                : Colors.grey[800],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isCurrentUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF137FEC),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '@${entry.username}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            
            // XP
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${entry.xpEarned}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF137FEC),
                  ),
                ),
                Text(
                  'XP',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitial() {
    return Center(
      child: Text(
        entry.displayName.isNotEmpty
            ? entry.displayName[0].toUpperCase()
            : entry.username[0].toUpperCase(),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: entry.isCurrentUser ? const Color(0xFF137FEC) : Colors.grey[600],
        ),
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.grey[600]!;
    }
  }
}
