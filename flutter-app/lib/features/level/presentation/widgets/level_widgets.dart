import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/domain/entities/level_entity.dart';
import 'package:lexilingo_app/features/level/services/level_calculator.dart';

/// Icon mapping for tier identifiers
String _getTierIcon(String iconIdentifier) {
  switch (iconIdentifier) {
    case 'seedling':
      return '🌱';
    case 'sprout':
      return '🌿';
    case 'tree':
      return '🌳';
    case 'forest':
      return '🌲';
    case 'star':
      return '⭐';
    case 'crown':
      return '👑';
    default:
      return '📚';
  }
}

/// Compact level badge for header display
class LevelBadge extends StatelessWidget {
  final String tierCode;
  final LevelTier tier;
  final double progress;
  final VoidCallback? onTap;

  const LevelBadge({
    super.key,
    required this.tierCode,
    required this.tier,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _getTierColor(tier),
              _getTierColor(tier).withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _getTierColor(tier).withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getTierIcon(tier.iconIdentifier),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 4),
            Text(
              tierCode,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTierColor(LevelTier tier) {
    final hex = tier.colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}

/// Full level progress card for home page
class LevelProgressCard extends StatelessWidget {
  final VoidCallback? onTap;

  const LevelProgressCard({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LevelProvider>(
      builder: (context, levelProvider, child) {
        final status = levelProvider.levelStatus;

        return GestureDetector(
          onTap: onTap ?? () => _showLevelDetails(context, status),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _getTierColor(status.currentTier).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getTierIcon(status.currentTier.iconIdentifier),
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.currentTier.code,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              status.currentTier.name,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: _getTierColor(status.currentTier),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          LevelCalculator.formatXP(status.totalXP),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'Total XP',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Progress bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          status.nextTier != null 
                              ? 'Progress to ${status.nextTier!.code}'
                              : 'Max Level Reached!',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textGrey,
                          ),
                        ),
                        if (status.nextTier != null)
                          Text(
                            '${status.xpInCurrentLevel}/${status.xpToNextLevel + status.xpInCurrentLevel} XP',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: status.progressPercentage,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getTierColor(status.currentTier),
                        ),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(status.progressPercentage * 100).toInt()}% complete',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textGrey,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getTierColor(LevelTier tier) {
    final hex = tier.colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  void _showLevelDetails(BuildContext context, LevelStatus status) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LevelDetailsSheet(status: status),
    );
  }
}

/// Level details bottom sheet
class LevelDetailsSheet extends StatelessWidget {
  final LevelStatus status;

  const LevelDetailsSheet({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Level icon
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _getTierColor(status.currentTier).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              _getTierIcon(status.currentTier.iconIdentifier),
              style: const TextStyle(fontSize: 48),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            status.currentTier.code,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            status.currentTier.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _getTierColor(status.currentTier),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          // XP Stats
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(context, LevelCalculator.formatXP(status.totalXP), 'Total XP'),
                Container(width: 1, height: 40, color: Colors.grey.shade200),
                _buildStatItem(context, '${status.xpInCurrentLevel}', 'Current Level'),
                Container(width: 1, height: 40, color: Colors.grey.shade200),
                _buildStatItem(context, '${status.xpToNextLevel}', 'To Next'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // All tiers
          Text(
            'Level Tiers',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...LevelTiers.allTiers.map((tier) => _buildTierRow(context, tier, tier.code == status.currentTier.code)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textGrey,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildTierRow(BuildContext context, LevelTier tier, bool isCurrent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCurrent 
            ? _getTierColor(tier).withValues(alpha: 0.1) 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isCurrent 
            ? Border.all(color: _getTierColor(tier)) 
            : null,
      ),
      child: Row(
        children: [
          Text(_getTierIcon(tier.iconIdentifier), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tier.code} - ${tier.name}',
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? _getTierColor(tier) : null,
                  ),
                ),
                Text(
                  '${LevelCalculator.formatXP(tier.minXP)} - ${tier.maxXP != null ? LevelCalculator.formatXP(tier.maxXP!) : "Max"} XP',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textGrey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
          ],
        ],
      ),
    );
  }

  Color _getTierColor(LevelTier tier) {
    final hex = tier.colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}
