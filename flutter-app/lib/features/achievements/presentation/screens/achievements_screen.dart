/// Achievements Screen - Display all achievements and user progress
library;

import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/achievements/presentation/theme/achievement_palette.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/achievements/presentation/providers/achievement_provider.dart';
import 'package:lexilingo_app/features/achievements/presentation/widgets/achievement_widgets.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/achievements/presentation/widgets/achievement_unlock_overlay.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final provider = context.read<AchievementProvider>();
    await provider.loadAll();
    if (!mounted || provider.error != null) return;
    final newlyUnlocked = await provider.checkAchievements();
    if (newlyUnlocked.isNotEmpty && mounted) {
      await AchievementUnlockOverlay.show(
        context,
        achievements: newlyUnlocked,
        onDismiss: provider.clearRecentlyUnlocked,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('achievements.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'achievements.refresh'.tr(),
          ),
        ],
      ),
      body: ContentWidth(
        child: Consumer<AchievementProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return LoadingScreen(
                message: 'achievements.loadingAchievements'.tr(),
              );
            }

            if (provider.error != null) {
              return EmptyStateWidget(
                title: 'notifications.somethingWentWrong'.tr(),
                description: provider.error!,
                actionLabel: 'common.retry'.tr(),
                onAction: _loadData,
              );
            }

            if (provider.allAchievements.isEmpty) {
              return RefreshIndicator(
                onRefresh: _loadData,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: EmptyStateWidget(
                          title: 'common.noData'.tr(),
                          actionLabel: 'achievements.refresh'.tr(),
                          onAction: _loadData,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            final categories = provider.achievementsByCategory;

            return RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // Progress header
                  SliverToBoxAdapter(
                    child: _buildProgressHeader(provider, theme),
                  ),

                  // Category sections (skip 'xp' — covered by Level Milestones)
                  for (final entry in categories.entries)
                    if (entry.key.toLowerCase() != 'xp')
                      ..._buildCategorySection(
                        context,
                        provider,
                        entry.key,
                        entry.value,
                      ),

                  // Bottom padding
                  const SliverPadding(
                    padding: EdgeInsets.only(bottom: AppSpacing.xl),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProgressHeader(AchievementProvider provider, ThemeData theme) {
    final percentage = provider.completionPercentage;
    final unlocked = provider.unlockedCount;
    final total = provider.totalCount;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'achievements.yourProgress'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.surfaceLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'achievements.unlockedCount'.tr(
                      namedArgs: {'unlocked': '$unlocked', 'total': '$total'},
                    ),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textInverted.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              AnimatedProgressRing(
                progress: percentage / 100,
                size: 70,
                strokeWidth: 8,
                backgroundColor: AppColors.textInverted.withValues(alpha: 0.24),
                progressColor: AppColors.textInverted,
                child: Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.surfaceLight,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategorySection(
    BuildContext context,
    AchievementProvider provider,
    String category,
    List<AchievementEntity> achievements,
  ) {
    final theme = Theme.of(context);
    final categoryName = _getCategoryDisplayName(category);
    final categoryIcon = _getCategoryIcon(category);

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Icon(categoryIcon, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Text(
                categoryName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${achievements.where((a) => provider.isUnlocked(a.id)).length}/${achievements.length}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 132,
            childAspectRatio: 0.75,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final achievement = achievements[index];
            final isUnlocked = provider.isUnlocked(achievement.id);
            return AchievementCard(
              achievement: achievement,
              isUnlocked: isUnlocked,
              onTap: () =>
                  _showAchievementDetails(context, achievement, isUnlocked),
            );
          }, childCount: achievements.length),
        ),
      ),
    ];
  }

  String _getCategoryDisplayName(String category) {
    switch (category.toLowerCase()) {
      case 'lesson':
      case 'lessons':
        return 'achievements.categoryLessons'.tr();
      case 'streak':
        return 'achievements.categoryStreaks'.tr();
      case 'vocabulary':
        return 'achievements.categoryVocabulary'.tr();
      case 'quiz':
        return 'achievements.categoryQuiz'.tr();
      case 'course':
        return 'achievements.categoryCourse'.tr();
      case 'voice':
        return 'achievements.categoryVoice'.tr();
      case 'level':
        return 'achievements.categoryLevel'.tr();
      case 'special':
        return 'achievements.categorySpecial'.tr();
      case 'skill':
        return 'achievements.categorySkill'.tr();
      case 'social':
        return 'achievements.categorySocial'.tr();
      case 'milestone':
        return 'achievements.categoryMilestone'.tr();
      default:
        return category[0].toUpperCase() + category.substring(1);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'lesson':
      case 'lessons':
        return Icons.menu_book;
      case 'streak':
        return Icons.local_fire_department;
      case 'vocabulary':
        return Icons.translate;
      case 'quiz':
        return Icons.quiz;
      case 'course':
        return Icons.school;
      case 'voice':
        return Icons.mic;
      case 'level':
        return Icons.trending_up;
      case 'special':
        return Icons.auto_awesome;
      case 'skill':
        return Icons.psychology;
      case 'social':
        return Icons.people;
      case 'milestone':
        return Icons.flag;
      default:
        return Icons.emoji_events;
    }
  }

  void _showAchievementDetails(
    BuildContext context,
    AchievementEntity achievement,
    bool isUnlocked,
  ) {
    final theme = Theme.of(context);
    final Color rarityColor = Color(achievement.rarityColorValue);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Badge
            AchievementBadge(
              achievement: achievement,
              isUnlocked: isUnlocked,
              size: 100,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Name
            Text(
              achievement.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Rarity badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: rarityColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                achievement.rarityDisplayName,
                style: TextStyle(
                  color: rarityColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Description
            Text(
              achievement.description,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Rewards
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (achievement.xpReward > 0)
                  _buildRewardBadge(
                    Icons.star,
                    '${achievement.xpReward} XP',
                    AppColors.warning,
                  ),
                if (achievement.xpReward > 0 && achievement.gemsReward > 0)
                  const SizedBox(width: AppSpacing.md),
                if (achievement.gemsReward > 0)
                  _buildRewardBadge(
                    Icons.diamond,
                    '${achievement.gemsReward} Gems',
                    AchievementPalette.cyan,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            // Status
            if (!isUnlocked)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'achievements.completeToUnlock'.tr(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: context.status.success,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'achievements.achievementUnlocked'.tr(),
                      style: TextStyle(
                        color: context.status.success,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text('achievements.share'.tr()),
                onPressed: () => _shareAchievement(achievement),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  void _shareAchievement(AchievementEntity achievement) {
    final text = 'achievements.shareText'.tr(
      namedArgs: {
        'name': achievement.name,
        'description': achievement.description,
      },
    );
    Share.share(text);
  }

  Widget _buildRewardBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
