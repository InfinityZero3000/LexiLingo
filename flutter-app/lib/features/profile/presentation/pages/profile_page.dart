import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lexilingo_app/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/user/presentation/pages/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final authProvider = context.read<AuthProvider>();
    final levelProvider = context.read<LevelProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final profileProvider = context.read<ProfileProvider>();

    // Sync level with user XP
    if (authProvider.currentUser != null) {
      levelProvider.updateLevel(authProvider.currentUser!.xp);
    }

    // Load progress stats
    await progressProvider.fetchMyProgress();
    
    // Load profile stats from backend
    await profileProvider.loadProfileData();
  }

  String _formatMemberSince(DateTime? createdAt) {
    if (createdAt == null) return 'Member';
    return 'Member since ${DateFormat('MMM yyyy').format(createdAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: GestureDetector(
          onTap: () {}, // Back if needed
          child: const Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.primary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              // Profile Header
              _buildProfileHeader(context, user),

              // Level Progress Card
              _buildLevelProgressCard(context),

              // Learning Stats
              _buildLearningStats(context, user),

              // Weekly Activity
              _buildWeeklyActivity(context),

              // Recent Badges
              _buildRecentBadges(context),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, dynamic user) {
    return Consumer<LevelProvider>(
      builder: (context, levelProvider, child) {
        final levelStatus = levelProvider.levelStatus;
        final tierName = '${levelStatus.currentTier.code} ${levelStatus.currentTier.name}';

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2), width: 4),
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                    child: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              user.avatarUrl!,
                              fit: BoxFit.cover,
                              width: 128,
                              height: 128,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                size: 64,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 64,
                            color: AppColors.primary,
                          ),
                  ),
                  if (user?.isVerified == true)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child:
                            const Icon(Icons.verified, color: Colors.white, size: 14),
                      ),
                    ),
                  // Level Badge
                  Positioned(
                    top: 0,
                    right: 0,
                    child: LevelBadge(
                      tierCode: levelStatus.currentTier.code,
                      tier: levelStatus.currentTier,
                      progress: levelStatus.progressPercentage / 100,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                user?.displayName ?? 'Guest User',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (user?.email != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    user.email,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                tierName,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatMemberSince(user?.createdAt),
                style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLevelProgressCard(BuildContext context) {
    return Consumer<LevelProvider>(
      builder: (context, levelProvider, child) {
        final levelStatus = levelProvider.levelStatus;
        final currentTier = levelStatus.currentTier;
        final nextTier = LevelCalculator.getNextTier(currentTier);
        final xpToNext = nextTier != null
            ? nextTier.minXP - levelStatus.totalXP
            : 0;
        final progressLabel = nextTier != null
            ? 'Progress to ${nextTier.code} ${nextTier.name}'
            : 'Maximum Level Reached';
        final xpLabel = nextTier != null
            ? '${levelProvider.getFormattedTotalXP()} / ${LevelCalculator.formatXP(nextTier.minXP)} XP'
            : '${levelProvider.getFormattedTotalXP()} XP';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(progressLabel,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(xpLabel, style: const TextStyle(fontSize: 14)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: levelStatus.progressPercentage / 100,
                  minHeight: 10,
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[700]
                      : const Color(0xFFDBE0E6),
                  valueColor: AlwaysStoppedAnimation(
                    _getTierColor(currentTier.code),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    nextTier != null ? '${LevelCalculator.formatXP(xpToNext)} XP to go' : 'Master Level!',
                    style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
                  ),
                  Text(
                    '${levelStatus.progressPercentage.toStringAsFixed(0)}% complete',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getTierColor(String tierCode) {
    switch (tierCode) {
      case 'A1':
        return Colors.green;
      case 'A2':
        return Colors.teal;
      case 'B1':
        return Colors.blue;
      case 'B2':
        return Colors.indigo;
      case 'C1':
        return Colors.purple;
      case 'C2':
        return Colors.amber;
      default:
        return AppColors.primary;
    }
  }

  Widget _buildLearningStats(BuildContext context, dynamic user) {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, child) {
        // Use stats from ProfileProvider (backend API)
        final stats = profileProvider.stats;
        final streak = stats?.currentStreak ?? user?.currentStreak ?? 0;
        final lessonsCompleted = stats?.totalLessonsCompleted ?? 0;
        final coursesCompleted = stats?.totalCoursesCompleted ?? 0;
        final vocabularyMastered = stats?.totalVocabularyMastered ?? 0;
        final testsPassed = stats?.totalTestsPassed ?? 0;
        final avgScore = stats?.averageTestScore ?? 0.0;

        // Show loading state
        if (profileProvider.isLoadingStats && stats == null) {
          return _buildLoadingStats(context);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Text(
                    'Learning Stats',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _buildStatCard(
                  context,
                  Icons.local_fire_department,
                  Colors.orange,
                  'Streak',
                  '$streak Days',
                  streak > 0 ? 'Keep it up!' : 'Start today!',
                ),
                _buildStatCard(
                  context,
                  Icons.menu_book,
                  Colors.blue,
                  'Lessons',
                  '$lessonsCompleted',
                  'Completed',
                ),
                _buildStatCard(
                  context,
                  Icons.school,
                  Colors.green,
                  'Courses',
                  '$coursesCompleted',
                  'Finished',
                ),
                _buildStatCard(
                  context,
                  Icons.abc,
                  Colors.purple,
                  'Vocabulary',
                  '$vocabularyMastered',
                  'Mastered',
                ),
                _buildStatCard(
                  context,
                  Icons.quiz,
                  Colors.teal,
                  'Tests',
                  '$testsPassed',
                  avgScore > 0 ? '${avgScore.toStringAsFixed(0)}% avg' : 'Passed',
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AchievementsScreen()),
                    );
                  },
                  child: _buildStatCard(
                    context,
                    Icons.stars,
                    Colors.amber,
                    'Badges',
                    '${stats?.totalCertificatesEarned ?? 0}',
                    'View all',
                    isAction: true,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoadingStats(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Learning Stats',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: List.generate(
            6,
            (index) => Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyActivity(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, child) {
        final activities = profileProvider.weeklyActivity;
        final isLoading = profileProvider.isLoadingActivity;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Weekly Activity',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Last 7 Days',
                      style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)
                ],
              ),
              child: isLoading && activities.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : activities.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'No activity data yet',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            // XP Chart
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: activities.map((activity) {
                                final maxXP = activities.map((a) => a.xpEarned).reduce((a, b) => a > b ? a : b);
                                final normalizedValue = maxXP > 0 ? activity.xpEarned / maxXP : 0.0;
                                final date = DateTime.parse(activity.date);
                                final dayLabel = DateFormat('E').format(date).substring(0, 1);
                                
                                return _buildChartBar(context, dayLabel, normalizedValue, activity.xpEarned);
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            // Summary stats
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildActivityStat(
                                  'Total XP',
                                  '${activities.fold<int>(0, (sum, a) => sum + a.xpEarned)}',
                                  Icons.star,
                                  Colors.amber,
                                ),
                                _buildActivityStat(
                                  'Lessons',
                                  '${activities.fold<int>(0, (sum, a) => sum + a.lessonsCompleted)}',
                                  Icons.menu_book,
                                  Colors.blue,
                                ),
                                _buildActivityStat(
                                  'Words',
                                  '${activities.fold<int>(0, (sum, a) => sum + a.vocabularyLearned)}',
                                  Icons.abc,
                                  Colors.green,
                                ),
                              ],
                            ),
                          ],
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActivityStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentBadges(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, provider, child) {
        final badges = provider.recentBadges;
        final isLoading = provider.isLoadingBadges;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Badges',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AchievementsScreen()),
                      );
                    },
                    child: const Text('View All'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 100,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : badges.isEmpty
                      ? _buildEmptyBadges()
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: badges.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final badge = badges[index];
                            return _buildBadgeItemFromEntity(badge);
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  /// Build empty badges placeholder
  Widget _buildEmptyBadges() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            'Complete lessons to earn badges!',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Build badge item from UserAchievementEntity
  Widget _buildBadgeItemFromEntity(dynamic badge) {
    final achievement = badge.achievement;
    final color = Color(achievement.rarityColorValue);
    final icon = _getBadgeIcon(achievement.category);
    
    return Tooltip(
      message: '${achievement.name}\n${badge.unlockedTimeAgo}',
      child: _buildBadgeItem(icon, color, achievement.name),
    );
  }

  /// Get icon for badge category
  IconData _getBadgeIcon(String category) {
    switch (category) {
      case 'lessons':
        return Icons.school;
      case 'streak':
        return Icons.local_fire_department;
      case 'vocabulary':
        return Icons.translate;
      case 'xp':
        return Icons.star;
      case 'quiz':
        return Icons.quiz;
      case 'course':
        return Icons.workspace_premium;
      case 'voice':
        return Icons.mic;
      default:
        return Icons.emoji_events;
    }
  }

  Widget _buildStatCard(BuildContext context, IconData icon, Color color, String title, String value, String subLabel, {bool isAction = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               Icon(icon, color: color, size: 20),
               const SizedBox(width: 8),
               Text(title, style: const TextStyle(color: AppColors.textGrey, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isAction ? AppColors.primary.withValues(alpha: 0.1) : const Color(0xFF078838).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4)
            ),
            child: Text(subLabel, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold,
              color: isAction ? AppColors.primary : const Color(0xFF078838)
            )),
          )
        ],
      ),
    );
  }

  Widget _buildChartBar(BuildContext context, String day, double pct, [int? xpValue]) {
    return Expanded(
      child: Column(
        children: [
          // Tooltip showing XP value
          if (xpValue != null && xpValue > 0)
            Text(
              '$xpValue',
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          if (xpValue != null && xpValue > 0) const SizedBox(height: 4),
          
          // Bar
          Container(
            width: 32,
            height: pct > 0 ? 60 * pct + 10 : 4,
            decoration: BoxDecoration(
              color: pct > 0
                  ? AppColors.primary.withValues(alpha: 0.3 + (pct * 0.7))
                  : Colors.grey[300],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
          const SizedBox(height: 8),
          
          // Day label
          Text(
            day,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeItem(IconData icon, Color color, String label, {bool isLocked = false}) {
     return Column(
       children: [
         Container(
           width: 64, height: 64,
           decoration: BoxDecoration(
             shape: BoxShape.circle,
             gradient: isLocked ? null : LinearGradient(colors: [color.withValues(alpha: 0.6), color], begin: Alignment.bottomLeft, end: Alignment.topRight),
             color: isLocked ? Colors.grey[200] : null,
             border: isLocked ? Border.all(color: Colors.grey, width: 2, style: BorderStyle.solid) : null,
             boxShadow: isLocked ? null : [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 4))]
           ),
           child: Icon(icon, color: isLocked ? Colors.grey : Colors.white, size: 30),
         ),
         const SizedBox(height: 8),
         Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
       ],
     );
  }
}

