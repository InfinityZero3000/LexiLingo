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
    GameType.wordScramble: 'https://images.unsplash.com/photo-1634128221889-82ed6efeb273?auto=format&fit=crop&q=80&w=400&h=300',
    GameType.fillBlank: 'https://images.unsplash.com/photo-1455390582262-044cdead27d8?auto=format&fit=crop&q=80&w=400&h=300',
    GameType.matching: 'https://images.unsplash.com/photo-1611162617474-5b21e879e113?auto=format&fit=crop&q=80&w=400&h=300',
    GameType.spellingBee: 'https://images.unsplash.com/photo-1473679808388-306abccfdbe8?auto=format&fit=crop&q=80&w=400&h=300',
    GameType.grammarQuiz: 'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?auto=format&fit=crop&q=80&w=400&h=300',
    GameType.hangman: 'https://images.unsplash.com/photo-1509062522246-3755977927d7?auto=format&fit=crop&q=80&w=400&h=300',
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
