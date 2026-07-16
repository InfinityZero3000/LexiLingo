import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';

/// Full-screen overlay shown when one or more achievements are unlocked.
///
/// Plays a star-burst Lottie animation, scales in the badge, and
/// auto-dismisses after [displayDuration]. Each achievement in the queue
/// is shown sequentially.
class AchievementUnlockOverlay extends StatefulWidget {
  final List<UnlockedAchievementModel> achievements;
  final VoidCallback onDismiss;
  final Duration displayDuration;

  const AchievementUnlockOverlay({
    super.key,
    required this.achievements,
    required this.onDismiss,
    this.displayDuration = const Duration(seconds: 3),
  });

  static Future<void> show(
    BuildContext context, {
    required List<UnlockedAchievementModel> achievements,
    required VoidCallback onDismiss,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Achievement',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => AchievementUnlockOverlay(
        achievements: achievements,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  State<AchievementUnlockOverlay> createState() =>
      _AchievementUnlockOverlayState();
}

class _AchievementUnlockOverlayState extends State<AchievementUnlockOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _badgeScale;
  late final Animation<double> _scaleAnim;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _badgeScale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _badgeScale, curve: Curves.elasticOut),
    );
    _playForCurrent();
  }

  void _playForCurrent() {
    _badgeScale.reset();
    _badgeScale.forward();
    Future.delayed(widget.displayDuration, _next);
  }

  void _next() {
    if (!mounted) return;
    if (_current < widget.achievements.length - 1) {
      setState(() => _current++);
      _playForCurrent();
    } else {
      widget.onDismiss();
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void dispose() {
    _badgeScale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final achievement = widget.achievements[_current];
    final rarityColor = _rarityColor(achievement.rarity);

    return GestureDetector(
      onTap: _next,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Lottie star-burst in background
            const Positioned.fill(
              child: IgnorePointer(
                child: LottieAnimationWidget.starBurst(),
              ),
            ),

            // Achievement card
            ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDarkElevated
                      : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: rarityColor.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                  border: Border.all(
                    color: rarityColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Rarity label
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: rarityColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        achievement.rarity.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: rarityColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Badge icon
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rarityColor.withValues(alpha: 0.15),
                        border: Border.all(
                          color: rarityColor.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _categoryIcon(achievement.category),
                        color: rarityColor,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // "Achievement Unlocked!" label
                    Text(
                      'Achievement Unlocked!',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColorRoles.textMuted(isDark),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Achievement name
                    Text(
                      achievement.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColorRoles.textPrimary(isDark),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Description
                    Text(
                      achievement.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColorRoles.textMuted(isDark),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Rewards row
                    if (achievement.xpReward > 0 || achievement.gemsReward > 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (achievement.xpReward > 0) ...[
                            const Icon(
                              Icons.star_rounded,
                              color: AppColors.warning,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '+${achievement.xpReward} XP',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                          if (achievement.xpReward > 0 &&
                              achievement.gemsReward > 0)
                            const SizedBox(width: 16),
                          if (achievement.gemsReward > 0) ...[
                            const Icon(
                              Icons.diamond_rounded,
                              color: AppColors.purple,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '+${achievement.gemsReward} gems',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.purple,
                              ),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 20),

                    // Tap to continue hint
                    Text(
                      widget.achievements.length > 1
                          ? 'Tap to continue (${_current + 1}/${widget.achievements.length})'
                          : 'Tap to continue',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColorRoles.textMuted(isDark).withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _rarityColor(String rarity) => switch (rarity.toLowerCase()) {
    'legendary' => const Color(0xFFFF6B00),
    'epic' => AppColors.purple,
    'rare' => AppColors.cefrB,
    _ => AppColors.cefrA,
  };

  IconData _categoryIcon(String category) => switch (category.toLowerCase()) {
    'streak' => Icons.local_fire_department_rounded,
    'lessons' => Icons.school_rounded,
    'social' => Icons.people_rounded,
    'games' => Icons.sports_esports_rounded,
    'vocabulary' => Icons.menu_book_rounded,
    'learning' => Icons.psychology_rounded,
    _ => Icons.emoji_events_rounded,
  };
}
