import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';

/// Leaderboard Podium Widget
/// Displays the top 3 users on a podium
class LeaderboardPodium extends StatelessWidget {
  final List<LeaderboardEntryEntity> topThree;

  const LeaderboardPodium({super.key, required this.topThree});

  @override
  Widget build(BuildContext context) {
    // Ensure we have at least placeholder data for 3 positions
    final first = topThree.isNotEmpty ? topThree[0] : null;
    final second = topThree.length > 1 ? topThree[1] : null;
    final third = topThree.length > 2 ? topThree[2] : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Row(
            children: const [
              Expanded(
                child: Center(
                  child: Text(
                    '2',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '1',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '3',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _buildPodiumItem(
                  context,
                  entry: second,
                  rank: 2,
                  podiumHeight: 94,
                  color: AppColors.slate200,
                  medalColor: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPodiumItem(
                  context,
                  entry: first,
                  rank: 1,
                  podiumHeight: 116,
                  color: AppColors.warning,
                  medalColor: AppColors.orange,
                  showCrown: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPodiumItem(
                  context,
                  entry: third,
                  rank: 3,
                  podiumHeight: 86,
                  color: AppColors.orange.withValues(alpha: 0.45),
                  medalColor: AppColors.deepOrange,
                ),
              ),
            ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCrown && entry != null)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            child: const Icon(
              Icons.emoji_events,
              color: AppColors.warning,
              size: 28,
            ),
          ),

        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: rank == 1 ? 60 : 50,
              height: rank == 1 ? 60 : 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
                color: entry != null
                    ? (entry.isCurrentUser
                          ? primaryColor.withValues(alpha: 0.18)
                          : Colors.grey[200])
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
                              errorBuilder: (_, __, ___) =>
                                  _buildInitialAvatar(context, entry),
                            ),
                          )
                        : _buildInitialAvatar(context, entry))
                  : Icon(
                      Icons.person_outline,
                      color: Colors.grey[400],
                      size: 24,
                    ),
            ),

            Positioned(
              bottom: -8,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: medalColor,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
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
                    style: TextStyle(
                      color: AppColors.surfaceLight,
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

        Text(
          entry?.displayName ?? '---',
          style: TextStyle(
            fontSize: 13,
            fontWeight: entry?.isCurrentUser == true
                ? FontWeight.bold
                : FontWeight.w500,
            color: entry?.isCurrentUser == true
                ? primaryColor
                : AppColors.textDark,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        if (entry != null)
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: AppColors.warmGradient),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${entry.xpEarned}',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.surfaceLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

        const SizedBox(height: 8),

        Container(
          height: podiumHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.22),
                color.withValues(alpha: 0.08),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Center(
            child: Text(
              '#$rank',
              style: TextStyle(
                color: _getRankColor(rank).withValues(alpha: 0.8),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialAvatar(
    BuildContext context,
    LeaderboardEntryEntity entry,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Text(
        entry.displayName.isNotEmpty
            ? entry.displayName[0].toUpperCase()
            : entry.username[0].toUpperCase(),
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: entry.isCurrentUser
              ? AppColorRoles.primary(isDark)
              : Colors.grey[600],
        ),
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return AppColors.orange;
      case 2:
        return AppColors.textMuted;
      case 3:
        return AppColors.warning;
      default:
        return AppColors.textGrey;
    }
  }
}

/// Leaderboard Entry Row Widget
class LeaderboardEntryRow extends StatelessWidget {
  final LeaderboardEntryEntity entry;
  final VoidCallback? onTap;

  const LeaderboardEntryRow({super.key, required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: entry.isCurrentUser
              ? primaryColor.withValues(alpha: 0.08)
              : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          border: Border.all(
            color: entry.isCurrentUser
                ? primaryColor.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getRankColor(entry.rank).withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _getRankColor(entry.rank),
                ),
              ),
            ),

            const SizedBox(width: 10),

            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: entry.isCurrentUser
                    ? primaryColor.withValues(alpha: 0.2)
                    : Colors.grey[200],
                border: entry.isCurrentUser
                    ? Border.all(color: primaryColor, width: 2)
                    : null,
              ),
              child: entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        entry.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildInitial(context),
                      ),
                    )
                  : _buildInitial(context),
            ),
            const SizedBox(width: 12),

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
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.surfaceLight,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${entry.lessonsCompleted} lessons completed',
                    style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),

            Container(
              constraints: const BoxConstraints(minWidth: 68),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${entry.xpEarned}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepOrange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitial(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Text(
        entry.displayName.isNotEmpty
            ? entry.displayName[0].toUpperCase()
            : entry.username[0].toUpperCase(),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: entry.isCurrentUser
              ? AppColorRoles.primary(isDark)
              : Colors.grey[600],
        ),
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return AppColors.orange;
      case 2:
        return AppColors.textMuted;
      case 3:
        return AppColors.warning;
      default:
        return AppColors.textGrey;
    }
  }
}
