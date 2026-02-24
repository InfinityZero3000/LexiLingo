/// Achievement Widgets - UI components for displaying achievements

import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';
import 'package:lexilingo_app/core/widgets/badge_generator.dart';
import 'package:lexilingo_app/features/achievements/data/badge_asset_mapper.dart';

/// Helper function to get IconData from badge icon identifier
IconData _getBadgeIcon(String? badgeIcon) {
  if (badgeIcon == null) return Icons.emoji_events;

  switch (badgeIcon.toLowerCase()) {
    // Trophy/Medal icons
    case 'trophy':
      return Icons.emoji_events;
    case 'medal':
      return Icons.military_tech;
    case 'crown':
      return Icons.workspace_premium;
    case 'award':
      return Icons.emoji_events_outlined;
      
    // Star icons
    case 'star':
      return Icons.star;
    case 'star_gold':
      return Icons.star_rate;
    case 'stars':
      return Icons.auto_awesome;
      
    // Fire/Energy icons
    case 'fire':
      return Icons.local_fire_department;
    case 'bolt':
    case 'lightning':
      return Icons.bolt;
    case 'flash':
      return Icons.flash_on;
      
    // Education icons
    case 'book':
      return Icons.menu_book;
    case 'library':
      return Icons.local_library;
    case 'dictionary':
      return Icons.book;
    case 'school':
      return Icons.school;
    case 'pencil':
      return Icons.edit;
      
    // Target/Check icons
    case 'target':
      return Icons.track_changes;
    case 'check':
    case 'check_circle':
      return Icons.check_circle;
    case 'verified':
      return Icons.verified;
      
    // Gem/Diamond icons
    case 'diamond':
      return Icons.diamond;
    case 'gem':
      return Icons.diamond_outlined;
      
    // Voice icons
    case 'mic':
    case 'microphone':
      return Icons.mic;
    case 'record':
      return Icons.fiber_manual_record;
    case 'speaker':
      return Icons.volume_up;
      
    // Progress icons
    case 'flag':
      return Icons.flag;
    case 'rocket':
      return Icons.rocket_launch;
    case 'trending':
      return Icons.trending_up;
      
    // Default fallback
    default:
      // Check if it's an emoji (fallback to trophy)
      if (badgeIcon.length <= 2 || badgeIcon.contains(RegExp(r'[\u{1F000}-\u{1FFFF}]', unicode: true))) {
        return Icons.emoji_events;
      }
      return Icons.emoji_events;
  }
}

/// Badge widget - displays a single achievement badge
/// Now supports both custom painted badges AND image assets
class AchievementBadge extends StatelessWidget {
  final AchievementEntity achievement;
  final bool isUnlocked;
  final VoidCallback? onTap;
  final double size;
  final bool useNewStyle; // Toggle between old and new style
  final bool preferImageAsset; // Prefer image asset over generated badge
  final bool useCdnFirst; // Prefer CDN over local assets

  const AchievementBadge({
    super.key,
    required this.achievement,
    this.isUnlocked = false,
    this.onTap,
    this.size = 80,
    this.useNewStyle = true, // Default to new style
    this.preferImageAsset = true, // Default to prefer image assets
    this.useCdnFirst = true, // Default to CDN first for better performance
  });

  @override
  Widget build(BuildContext context) {
    if (preferImageAsset) {
      // Prefer slug (stable ID) over id (UUID) for badge asset lookup
      final lookupKey = achievement.slug ?? achievement.id;
      
      // Priority 1: Network image from backend API (badgeIcon field)
      if (achievement.badgeIcon != null && achievement.badgeIcon!.isNotEmpty) {
        return _buildNetworkBadge(achievement.badgeIcon!);
      }
      
      // Priority 2: CDN URL (if useCdnFirst is true)
      if (useCdnFirst) {
        final cdnUrl = BadgeNetworkImages.getBadgeUrl(lookupKey);
        if (cdnUrl != null) {
          return _buildNetworkBadge(cdnUrl);
        }
      }
      
      // Priority 3: Local asset
      final assetPath = BadgeAssetMapper.getBadgeAsset(lookupKey);
      if (assetPath != null) {
        return _buildImageAssetBadge(assetPath);
      }
    }

    // Fall back to generated badge
    if (useNewStyle) {
      return _buildNewStyleBadge();
    }
    return _buildClassicBadge();
  }

  /// Build badge from network URL (CDN or backend)
  Widget _buildNetworkBadge(String imageUrl) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Badge image from network
            ClipOval(
              child: Image.network(
                imageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  // Fallback to local asset or generated badge
                  final lookupKey = achievement.slug ?? achievement.id;
                  final assetPath = BadgeAssetMapper.getBadgeAsset(lookupKey);
                  if (assetPath != null) {
                    return Image.asset(
                      assetPath,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildNewStyleBadge(),
                    );
                  }
                  return _buildNewStyleBadge();
                },
              ),
            ),
            // Lock overlay if not unlocked
            if (!isUnlocked)
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                child: Icon(
                  Icons.lock,
                  size: size * 0.4,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build badge from local image asset
  Widget _buildImageAssetBadge(String assetPath) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Badge image from asset
            ClipOval(
              child: Image.asset(
                assetPath,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback to generated badge if image fails to load
                  return _buildNewStyleBadge();
                },
              ),
            ),
            // Lock overlay if not unlocked
            if (!isUnlocked)
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                child: Icon(
                  Icons.lock,
                  size: size * 0.4,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// New generated badge with custom painting
  Widget _buildNewStyleBadge() {
    return SmartAchievementBadge(
      category: achievement.category,
      badgeIcon: achievement.badgeIcon,
      badgeColor: achievement.badgeColor,
      rarity: achievement.rarity,
      conditionValue: achievement.conditionValue,
      isUnlocked: isUnlocked,
      size: size,
      onTap: onTap,
    );
  }

  /// Classic badge style (fallback)
  Widget _buildClassicBadge() {
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
