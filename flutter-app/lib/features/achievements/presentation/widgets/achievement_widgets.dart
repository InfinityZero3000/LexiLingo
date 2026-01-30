/// Achievement Widgets - UI components for displaying achievements

import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';

/// Helper function to get IconData from badge icon identifier
IconData _getBadgeIcon(String? badgeIcon) {
  if (badgeIcon == null) return Icons.emoji_events;

  switch (badgeIcon) {
    case 'trophy':
      return Icons.emoji_events;
    case 'star':
      return Icons.star;
    case 'diamond':
      return Icons.diamond;
    case 'medal':
      return Icons.military_tech;
    case 'fire':
      return Icons.local_fire_department;
    case 'bolt':
      return Icons.bolt;
    default:
      return Icons.emoji_events;
  }
}

/// Badge widget - displays a single achievement badge
class AchievementBadge extends StatelessWidget {
  final AchievementEntity achievement;
  final bool isUnlocked;
  final VoidCallback? onTap;
  final double size;

  const AchievementBadge({
    super.key,
    required this.achievement,
    this.isUnlocked = false,
    this.onTap,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = achievement.badgeColor != null
        ? Color(
            int.parse(
              achievement.badgeColor!.replaceFirst('#', 'FF'),
              radix: 16,
            ),
          )
        : Color(achievement.rarityColorValue);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isUnlocked
              ? badgeColor.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
          border: Border.all(
            color: isUnlocked ? badgeColor : Colors.grey,
            width: 3,
          ),
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: badgeColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: isUnlocked
              ? Icon(
                  _getBadgeIcon(achievement.badgeIcon),
                  size: size * 0.4,
                  color: Colors.white,
                )
              : Icon(Icons.lock, size: size * 0.35, color: Colors.grey),
        ),
      ),
    );
  }
}

/// Card widget for displaying achievement in a grid
class AchievementCard extends StatelessWidget {
  final AchievementEntity achievement;
  final bool isUnlocked;
  final VoidCallback? onTap;

  const AchievementCard({
    super.key,
    required this.achievement,
    this.isUnlocked = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color rarityColor = Color(achievement.rarityColorValue);

    return Card(
      elevation: isUnlocked ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isUnlocked ? rarityColor : Colors.grey.shade300,
          width: isUnlocked ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AchievementBadge(
                achievement: achievement,
                isUnlocked: isUnlocked,
                size: 50,
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  achievement.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isUnlocked ? null : Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: rarityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  achievement.rarityDisplayName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: rarityColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Achievement unlock popup with confetti
class AchievementUnlockPopup extends StatefulWidget {
  final UnlockedAchievementModel achievement;
  final VoidCallback? onDismiss;

  const AchievementUnlockPopup({
    super.key,
    required this.achievement,
    this.onDismiss,
  });

  @override
  State<AchievementUnlockPopup> createState() => _AchievementUnlockPopupState();
}

class _AchievementUnlockPopupState extends State<AchievementUnlockPopup> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final achievement = widget.achievement;
    final Color badgeColor = achievement.badgeColor != null
        ? Color(
            int.parse(
              achievement.badgeColor!.replaceFirst('#', 'FF'),
              radix: 16,
            ),
          )
        : Colors.amber;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Background overlay
        GestureDetector(
          onTap: widget.onDismiss,
          child: Container(color: Colors.black54),
        ),
        // Confetti
        ConfettiWidget(
          confettiController: _confettiController,
          blastDirectionality: BlastDirectionality.explosive,
          shouldLoop: false,
          colors: const [
            Colors.green,
            Colors.blue,
            Colors.pink,
            Colors.orange,
            Colors.purple,
            Colors.yellow,
          ],
          numberOfParticles: 30,
        ),
        // Popup content
        Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: badgeColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Text(
                  'Achievement Unlocked!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
                const SizedBox(height: 24),
                // Badge
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: badgeColor.withValues(alpha: 0.2),
                    border: Border.all(color: badgeColor, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: badgeColor.withValues(alpha: 0.5),
                        blurRadius: 15,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _getBadgeIcon(achievement.badgeIcon),
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Name
                Text(
                  achievement.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Description
                Text(
                  achievement.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Rewards
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (achievement.xpReward > 0) ...[
                      _RewardChip(
                        icon: Icons.star,
                        value: '+${achievement.xpReward} XP',
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (achievement.gemsReward > 0)
                      _RewardChip(
                        icon: Icons.diamond,
                        value: '+${achievement.gemsReward}',
                        color: Colors.cyan,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                // Close button
                ElevatedButton(
                  onPressed: widget.onDismiss,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: badgeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Awesome!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RewardChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _RewardChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

/// Mini badge widget for showing on profile/home
class AchievementMiniCard extends StatelessWidget {
  final UserAchievementEntity userAchievement;
  final VoidCallback? onTap;

  const AchievementMiniCard({
    super.key,
    required this.userAchievement,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final achievement = userAchievement.achievement;
    final Color badgeColor = achievement.badgeColor != null
        ? Color(
            int.parse(
              achievement.badgeColor!.replaceFirst('#', 'FF'),
              radix: 16,
            ),
          )
        : Color(achievement.rarityColorValue);

    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: '${achievement.name}\n${achievement.description}',
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: badgeColor.withValues(alpha: 0.2),
            border: Border.all(color: badgeColor, width: 2),
          ),
          child: Center(
            child: Icon(
              _getBadgeIcon(achievement.badgeIcon),
              size: 24,
              color: badgeColor,
            ),
          ),
        ),
      ),
    );
  }
}
