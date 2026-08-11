import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/achievements/data/badge_asset_mapper.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:lexilingo_app/features/achievements/presentation/widgets/achievement_widgets.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';

class RecentBadgesSection extends StatefulWidget {
  const RecentBadgesSection({super.key});

  @override
  State<RecentBadgesSection> createState() => _RecentBadgesSectionState();
}

class _RecentBadgesSectionState extends State<RecentBadgesSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _badgeShineController;

  @override
  void initState() {
    super.initState();
    _badgeShineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _badgeShineController.dispose();
    super.dispose();
  }

  bool _hasRenderableBadgeImage(UserAchievementEntity badge) {
    final achievement = badge.achievement;

    if (achievement.category.toLowerCase() == 'xp') {
      return false;
    }

    final networkBadge = achievement.badgeIcon?.trim();
    final networkBadgeUri = networkBadge != null && networkBadge.isNotEmpty
        ? Uri.tryParse(networkBadge)
        : null;
    final hasValidNetworkBadge =
        networkBadgeUri != null &&
        (networkBadgeUri.scheme == 'http' ||
            networkBadgeUri.scheme == 'https') &&
        networkBadgeUri.host.isNotEmpty;
    if (hasValidNetworkBadge) {
      return true;
    }

    final lookupKey = (achievement.slug ?? achievement.id).trim();
    if (lookupKey.isEmpty) {
      return false;
    }

    return BadgeAssetMapper.hasRenderableBadge(lookupKey);
  }

  /// Build empty badges placeholder
  Widget _buildEmptyBadges() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.emoji_events_outlined,
            size: 40,
            color: AppColors.grey500,
          ),
          const SizedBox(height: 8),
          Text(
            'profile.completeLessonsToEarnBadges'.tr(),
            style: const TextStyle(color: AppColors.grey600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Build badge item from UserAchievementEntity
  Widget _buildBadgeItemFromEntity(UserAchievementEntity badge) {
    final achievement = badge.achievement;
    const badgeSize = 64.0;
    final badgeMask = _buildBadgeShineMask(badge, badgeSize);

    return Tooltip(
      message: '${achievement.name}\n${badge.unlockedTimeAgo}',
      child: Column(
        children: [
          SizedBox(
            width: badgeSize,
            height: badgeSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AchievementBadge(
                  achievement: achievement,
                  isUnlocked: true,
                  size: badgeSize,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _badgeShineController,
                      builder: (context, child) {
                        // Smaller sweep portion => longer idle pause per cycle.
                        const sweepPortion = 0.62;
                        final progress = _badgeShineController.value;
                        final isSweeping = progress < sweepPortion;
                        final sweepT = isSweeping
                            ? Curves.easeInOut.transform(
                                progress / sweepPortion,
                              )
                            : 1.0;
                        final position = isSweeping
                            ? lerpDouble(-1.6, 1.6, sweepT)!
                            : 2.4;

                        return ShaderMask(
                          // Apply shine only where the badge image has alpha.
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment(position - 0.45, -1.0),
                              end: Alignment(position + 0.45, 1.0),
                              colors: [
                                AppColors.surfaceLight.withValues(alpha: 0),
                                AppColors.surfaceLight.withValues(alpha: 0.06),
                                AppColors.surfaceLight.withValues(alpha: 0.56),
                                AppColors.surfaceLight.withValues(alpha: 0.06),
                                AppColors.surfaceLight.withValues(alpha: 0),
                              ],
                              stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
                            ).createShader(bounds);
                          },
                          child: child,
                        );
                      },
                      child: badgeMask,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            achievement.name,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeShineMask(UserAchievementEntity badge, double badgeSize) {
    final achievement = badge.achievement;

    final networkBadge = achievement.badgeIcon?.trim();
    final networkBadgeUri = networkBadge != null && networkBadge.isNotEmpty
        ? Uri.tryParse(networkBadge)
        : null;
    final hasValidNetworkBadge =
        networkBadgeUri != null &&
        (networkBadgeUri.scheme == 'http' ||
            networkBadgeUri.scheme == 'https') &&
        networkBadgeUri.host.isNotEmpty;

    if (hasValidNetworkBadge) {
      return ClipOval(
        child: Image.network(
          networkBadge!,
          width: badgeSize,
          height: badgeSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }

    final lookupKey = (achievement.slug ?? achievement.id).trim();
    final assetPath = BadgeAssetMapper.getBadgeAsset(lookupKey);
    if (assetPath != null) {
      return ClipOval(
        child: Image.asset(
          assetPath,
          width: badgeSize,
          height: badgeSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, provider, child) {
        final badges = provider.recentBadges;
        final isLoading = provider.isLoadingBadges;
        final visibleBadges = badges.where(_hasRenderableBadgeImage).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'profile.recentBadges'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AchievementsScreen(),
                        ),
                      );
                    },
                    child: Text('achievements.viewAll'.tr()),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 100,
              child: isLoading
                  ? ShimmerContainer(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: 4,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          return const SkeletonCircle(size: 80);
                        },
                      ),
                    )
                  : visibleBadges.isEmpty
                  ? _buildEmptyBadges()
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: visibleBadges.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final badge = visibleBadges[index];
                        return _buildBadgeItemFromEntity(badge);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
