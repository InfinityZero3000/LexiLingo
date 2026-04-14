import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';

/// Game selection card used in the hub grid.
///
/// Shows game icon, name, description, and best score.
/// Gradient background is determined by game type.
class GameCard extends StatelessWidget {
  final GameType gameType;
  final int? bestScore;
  final VoidCallback? onTap;

  const GameCard({
    super.key,
    required this.gameType,
    this.bestScore,
    this.onTap,
  });

  static const Map<GameType, List<Color>> _gradients = {
    GameType.wordScramble: [AppColors.primary, Color(0xFF38B2FF)],
    GameType.fillBlank: [Color(0xFF078838), Color(0xFF34C25A)],
    GameType.matching: [AppColors.purple, Color(0xFFCE93D8)],
    GameType.spellingBee: [Color(0xFFF57C00), Color(0xFFFFB74D)],
    GameType.grammarQuiz: [Color(0xFF0288D1), Color(0xFF4FC3F7)],
    GameType.hangman: [AppColors.errorDark, Color(0xFFEF9A9A)],
  };

  @override
  Widget build(BuildContext context) {
    final colors =
        _gradients[gameType] ?? [AppColors.primary, AppColors.primary];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(gameType.icon, color: Colors.white, size: 28),
                if (bestScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.white, size: 11),
                        const SizedBox(width: 2),
                        Text(
                          '$bestScore',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              gameType.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                gameType.description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Play',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
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
