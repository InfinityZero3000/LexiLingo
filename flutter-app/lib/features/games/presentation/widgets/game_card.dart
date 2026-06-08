import 'package:easy_localization/easy_localization.dart';
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

  static const Map<GameType, String> _bgImages = {
    // Scrabble letter tiles on wooden surface — word scramble game
    GameType.wordScramble: 'https://images.unsplash.com/photo-1611532736597-de2d4265fba3?auto=format&fit=crop&q=80&w=400&h=300',
    // Open notebook with pen — fill-in-the-blank writing exercise
    GameType.fillBlank: 'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?auto=format&fit=crop&q=80&w=400&h=300',
    // Playing cards spread out — matching/memory card game
    GameType.matching: 'https://images.unsplash.com/photo-1606167668584-78701c57f13d?auto=format&fit=crop&q=80&w=400&h=300',
    // Macro bee on flower — spelling bee game
    GameType.spellingBee: 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&q=80&w=400&h=300',
    // Colorful books stacked — grammar quiz / study
    GameType.grammarQuiz: 'https://images.unsplash.com/photo-1524995997946-a1c2e315a42f?auto=format&fit=crop&q=80&w=400&h=300',
    // Letter tiles on table — hangman word-guessing game
    GameType.hangman: 'https://images.unsplash.com/photo-1517770413964-df8ca61194a6?auto=format&fit=crop&q=80&w=400&h=300',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors =
        _gradients[gameType] ?? [AppColors.primary, AppColors.primary];
    final foregroundColor = AppColors.textInverted;
    final secondaryForeground = foregroundColor.withValues(alpha: 0.85);
    final playChipBg = isDark
        ? Colors.black.withValues(alpha: 0.30)
        : Colors.white.withValues(alpha: 0.92);
    final playChipFg = isDark ? AppColors.textInverted : AppColors.textDark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background Image
              if (_bgImages[gameType] != null)
                Image.network(
                  _bgImages[gameType]!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              // Gradient Overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.first.withValues(alpha: 0.85),
                      colors.last.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(gameType.icon, color: foregroundColor, size: 28),
                        if (bestScore != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: foregroundColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star,
                                    color: foregroundColor, size: 11),
                                const SizedBox(width: 2),
                                Text(
                                  '$bestScore',
                                  style: TextStyle(
                                    color: foregroundColor,
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
                      style: TextStyle(
                        color: foregroundColor,
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
                            color: secondaryForeground, fontSize: 11),
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
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: playChipBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'games.play'.tr(),
                            style: TextStyle(
                              color: playChipFg,
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
            ],
          ),
        ),
      ),
    );
  }
}
