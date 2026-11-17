import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/games/presentation/theme/game_palette.dart';
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
    GameType.wordScramble: GamePalette.skyGradient,
    GameType.fillBlank: GamePalette.fillBlankGradient,
    GameType.matching: GamePalette.matchingGradient,
    GameType.spellingBee: GamePalette.spellingBeeGradient,
    GameType.grammarQuiz: GamePalette.grammarQuizGradient,
    GameType.hangman: GamePalette.hangmanGradient,
  };

  static const Map<GameType, String> _bgImages = {
    // Scrabble letter tiles on wooden surface — word scramble game
    GameType.wordScramble:
        'https://images.unsplash.com/photo-1611532736597-de2d4265fba3?auto=format&fit=crop&q=80&w=400&h=300',
    // Open notebook with pen — fill-in-the-blank writing exercise
    GameType.fillBlank:
        'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?auto=format&fit=crop&q=80&w=400&h=300',
    // Playing cards spread out — matching/memory card game
    GameType.matching:
        'https://images.unsplash.com/photo-1606167668584-78701c57f13d?auto=format&fit=crop&q=80&w=400&h=300',
    // Macro bee on flower — spelling bee game
    GameType.spellingBee:
        'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&q=80&w=400&h=300',
    // Colorful books stacked — grammar quiz / study
    GameType.grammarQuiz:
        'https://images.unsplash.com/photo-1524995997946-a1c2e315a42f?auto=format&fit=crop&q=80&w=400&h=300',
    // Letter tiles on table — hangman word-guessing game
    GameType.hangman:
        'https://images.unsplash.com/photo-1517770413964-df8ca61194a6?auto=format&fit=crop&q=80&w=400&h=300',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors =
        _gradients[gameType] ?? [AppColors.primary, AppColors.primary];
    final foregroundColor = AppColors.textInverted;
    final secondaryForeground = foregroundColor.withValues(alpha: 0.85);
    final playChipBg = isDark
        ? Theme.of(context).shadowColor.withValues(alpha: 0.30)
        : AppColors.textInverted.withValues(alpha: 0.92);
    final playChipFg = isDark ? AppColors.textInverted : AppColors.textDark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
                padding: const EdgeInsets.all(AppSpacing.lg),
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
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: foregroundColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  color: foregroundColor,
                                  size: 11,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '$bestScore',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: foregroundColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      gameType.displayName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        gameType.description,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: secondaryForeground,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: playChipBg,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text(
                            'games.play'.tr(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: playChipFg,
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
