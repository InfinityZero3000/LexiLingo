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
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class RecentBadgesSection extends StatefulWidget {
  const RecentBadgesSection({super.key});

  @override
  State<RecentBadgesSection> createState() => _RecentBadgesSectionState();
}

class _RecentBadgesSectionState extends State<RecentBadgesSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _badgeShineController;
  bool _shinePlayed = false;

  @override
  void initState() {
    super.initState();
    _badgeShineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
  }

  @override
  void dispose() {
    _badgeShineController.dispose();
    super.dispose();
  }

  /// One sweep only: a looping shine repaints every badge on every frame for as
  /// long as the tab is alive, which on the web makes the whole page stutter.
  void _playShineOnce() {
    if (_shinePlayed) return;
    _shinePlayed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _badgeShineController.forward();
    });
  }

  bool _isVisible(UserAchievementEntity badge) =>
      badge.achievement.category.toLowerCase() != 'xp';

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
          const SizedBox(height: AppSpacing.sm),
          Text(
            'profile.completeLessonsToEarnBadges'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
                        if (progress == 0 || progress >= sweepPortion) {
                          return const SizedBox.shrink();
                        }
                        final position = lerpDouble(
                          -1.6,
                          1.6,
                          Curves.easeInOut.transform(progress / sweepPortion),
                        )!;

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
          const SizedBox(height: AppSpacing.sm),
          Text(
            achievement.name,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Only supplies the alpha the shine is masked with; the badge itself, or
  /// its placeholder, is drawn by [AchievementBadge] underneath.
  Widget _buildBadgeShineMask(UserAchievementEntity badge, double badgeSize) {
    final achievement = badge.achievement;
    final image = resolveBadgeImage(
      slug: achievement.slug ?? achievement.id,
      badgeIcon: achievement.badgeIcon,
    );
    switch (image.kind) {
      case BadgeImageKind.asset:
        return ClipOval(
          child: Image.asset(
            image.value!,
            width: badgeSize,
            height: badgeSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        );
      case BadgeImageKind.network:
        return ClipOval(
          child: Image.network(
            image.value!,
            width: badgeSize,
            height: badgeSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        );
      case BadgeImageKind.none:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, provider, child) {
        final badges = provider.recentBadges;
        final isLoading = provider.isLoadingBadges;
        final visibleBadges = badges.where(_isVisible).toList();
        if (visibleBadges.isNotEmpty) _playShineOnce();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'profile.recentBadges'.tr(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
              height: 116,
              // A reload keeps what is on screen instead of flashing a skeleton.
              child: isLoading && visibleBadges.isEmpty
                  ? ShimmerContainer(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        itemCount: 4,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.lg),
                        itemBuilder: (context, index) {
                          return const SkeletonCircle(size: 80);
                        },
                      ),
                    )
                  : visibleBadges.isEmpty
                  ? _buildEmptyBadges()
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // Room above/below so the badge shadow isn't clipped.
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: visibleBadges.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.lg),
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
