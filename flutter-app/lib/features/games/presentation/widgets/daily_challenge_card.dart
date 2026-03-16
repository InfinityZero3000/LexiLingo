import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';

/// Daily challenge card displayed on the Games Hub.
///
/// Shows the challenge game type icon, description, 2x XP bonus badge,
/// a countdown label, and a completed checkmark state.
class DailyChallengeCard extends StatelessWidget {
  final DailyChallenge challenge;
  final VoidCallback onTap;

  const DailyChallengeCard({
    super.key,
    required this.challenge,
    required this.onTap,
  });

  /// Map apiKey → matching GameType, returning null when unknown.
  static GameType? _gameTypeFromKey(String key) {
    for (final t in GameType.values) {
      if (t.apiKey == key) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final gameType = _gameTypeFromKey(challenge.gameType);
    final icon = gameType?.icon ?? Icons.sports_esports_rounded;
    final completed = challenge.completed;

    return GestureDetector(
      onTap: completed ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          gradient: completed
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF137FEC), Color(0xFF5B9BF5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: completed ? AppColors.grey200 : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: completed
              ? []
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: completed
                    ? AppColors.grey300
                    : Colors.white.withValues(alpha: 0.2),
              ),
              alignment: Alignment.center,
              child: completed
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.greenSuccess,
                      size: 28,
                    )
                  : Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),

            // Description + timer
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    completed ? 'Challenge completed!' : 'Daily Challenge',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: completed ? AppColors.textGrey : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    challenge.description,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: completed ? AppColors.textDark : Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Resets tomorrow',
                    style: TextStyle(
                      fontSize: 11,
                      color: completed
                          ? AppColors.textGrey
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // 2x XP badge (only when incomplete)
            if (!completed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentYellow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${challenge.bonusMultiplier}x',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const Text(
                      'XP',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
            else
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.greenSuccess,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
