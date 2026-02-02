/// Achievements Screen - Display all achievements and user progress

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/achievements/presentation/providers/achievement_provider.dart';
import 'package:lexilingo_app/features/achievements/presentation/widgets/achievement_widgets.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';

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
    await provider.loadMyAchievements();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<AchievementProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const LoadingScreen(message: 'Loading achievements...');
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(provider.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadData,
                    child: const Text('Retry'),
                  ),
                ],
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

                // Category sections
                for (final entry in categories.entries)
                  ..._buildCategorySection(
                    context,
                    provider,
                    entry.key,
                    entry.value,
                  ),

                // Bottom padding
                const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressHeader(AchievementProvider provider, ThemeData theme) {
    final percentage = provider.completionPercentage;
    final unlocked = provider.unlockedCount;
    final total = provider.totalCount;

    return Container(
      margin: const EdgeInsets.all(16),
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
        borderRadius: BorderRadius.circular(16),
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
                    'Your Progress',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$unlocked / $total Achievements',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              AnimatedProgressRing(
                progress: percentage / 100,
                size: 70,
                strokeWidth: 8,
                backgroundColor: Colors.white24,
                progressColor: Colors.white,
                child: Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Icon(categoryIcon, size: 24),
              const SizedBox(width: 8),
              Text(
                categoryName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${achievements.where((a) => provider.isUnlocked(a.id)).length}/${achievements.length}',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
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
        return 'Lessons';
      case 'streak':
        return 'Streaks';
      case 'vocabulary':
        return 'Vocabulary';
      case 'xp':
        return 'Experience Points';
      case 'quiz':
        return 'Quiz Performance';
      case 'course':
        return 'Course Completion';
      case 'voice':
        return 'Voice Practice';
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
      case 'xp':
        return Icons.star;
      case 'quiz':
        return Icons.quiz;
      case 'course':
        return Icons.school;
      case 'voice':
        return Icons.mic;
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Badge
            AchievementBadge(
              achievement: achievement,
              isUnlocked: isUnlocked,
              size: 100,
            ),
            const SizedBox(height: 16),
            // Name
            Text(
              achievement.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            // Rarity badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: rarityColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                achievement.rarityDisplayName,
                style: TextStyle(
                  color: rarityColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Description
            Text(
              achievement.description,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Rewards
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (achievement.xpReward > 0)
                  _buildRewardBadge(
                    Icons.star,
                    '${achievement.xpReward} XP',
                    Colors.amber,
                  ),
                if (achievement.xpReward > 0 && achievement.gemsReward > 0)
                  const SizedBox(width: 12),
                if (achievement.gemsReward > 0)
                  _buildRewardBadge(
                    Icons.diamond,
                    '${achievement.gemsReward} Gems',
                    Colors.cyan,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            // Status
            if (!isUnlocked)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Complete to unlock this achievement!',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Achievement Unlocked!',
                    style: TextStyle(
                      color: Colors.green[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
