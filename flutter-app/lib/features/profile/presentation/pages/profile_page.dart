import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:lexilingo_app/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/gamification/gamification.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_ui_components.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/social/social.dart';
import 'package:lexilingo_app/features/user/presentation/pages/settings_page.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart' as glass;
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
    final gamificationProvider = context.read<GamificationProvider>();

    // Sync level with user XP
    if (authProvider.currentUser != null) {
      levelProvider.updateLevel(authProvider.currentUser!.xp);
    }

    // Load progress stats
    await progressProvider.fetchMyProgress();
    
    // Load profile stats from backend
    await profileProvider.loadProfileData();
    
    // Load gamification data (wallet, etc.)
    await gamificationProvider.loadWallet();
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
          // Wallet/Gems Button
          Consumer<GamificationProvider>(
            builder: (context, gamification, _) {
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WalletScreen()),
                ),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.diamond, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${gamification.wallet?.gems ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
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

              // Quick Actions (Shop, Leaderboard, Social, Wallet)
              _buildQuickActions(context),

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

  /// Quick Actions Grid - Navigate to new gamification/social features
  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildQuickActionButton(
            context,
            icon: Icons.store,
            label: 'Shop',
            color: const Color(0xFFF59E0B),
            gradient: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShopScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _buildQuickActionButton(
            context,
            icon: Icons.leaderboard,
            label: 'Ranks',
            color: const Color(0xFF10B981),
            gradient: const [Color(0xFF10B981), Color(0xFF059669)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _buildQuickActionButton(
            context,
            icon: Icons.people,
            label: 'Friends',
            color: const Color(0xFF3B82F6),
            gradient: const [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SocialScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _buildQuickActionButton(
            context,
            icon: Icons.account_balance_wallet,
            label: 'Wallet',
            color: const Color(0xFF8B5CF6),
            gradient: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
        final progress = levelStatus.progressPercentage / 100;

        return Container(
          margin: const EdgeInsets.all(16),
          child: Stack(
            children: [
              // Glassmorphic Background Card
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.15),
                          const Color(0xFF6366F1).withValues(alpha: 0.1),
                          Colors.white.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Avatar with animated progress ring
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Progress Ring
                            glass.AnimatedProgressRing(
                              progress: progress,
                              size: 140,
                              strokeWidth: 6,
                              gradientColors: const [
                                Color(0xFF137FEC),
                                Color(0xFF6366F1),
                                Color(0xFF8B5CF6),
                              ],
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                                      ? Image.network(
                                          user.avatarUrl!,
                                          fit: BoxFit.cover,
                                          width: 120,
                                          height: 120,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: AppColors.primary.withValues(alpha: 0.2),
                                            child: const Icon(
                                              Icons.person,
                                              size: 60,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          color: AppColors.primary.withValues(alpha: 0.2),
                                          child: const Icon(
                                            Icons.person,
                                            size: 60,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            // Verified Badge
                            if (user?.isVerified == true)
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF137FEC), Color(0xFF6366F1)],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.verified, color: Colors.white, size: 16),
                                ),
                              ),
                            // Level Badge
                            Positioned(
                              top: 0,
                              right: 0,
                              child: LevelBadge(
                                tierCode: levelStatus.currentTier.code,
                                tier: levelStatus.currentTier,
                                progress: progress,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // User Name
                        Text(
                          user?.displayName ?? 'Guest User',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Email
                        if (user?.email != null)
                          Text(
                            user.email,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Tier Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _getTierColor(levelStatus.currentTier.code),
                                _getTierColor(levelStatus.currentTier.code).withValues(alpha: 0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: _getTierColor(levelStatus.currentTier.code).withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getTierIcon(levelStatus.currentTier.code),
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tierName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Member Since
                        Text(
                          _formatMemberSince(user?.createdAt),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Social Stats Row
                        _buildSocialStatsRow(context),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Social stats row showing XP, followers, following
  Widget _buildSocialStatsRow(BuildContext context) {
    return Consumer2<LevelProvider, ProfileProvider>(
      builder: (context, levelProvider, profileProvider, _) {
        final stats = profileProvider.stats;
        final totalXP = levelProvider.levelStatus.totalXP;
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            AnimatedSocialStat(
              value: LevelCalculator.formatXP(totalXP),
              label: 'XP',
              icon: Icons.star,
              color: const Color(0xFFF59E0B),
            ),
            Container(
              height: 40,
              width: 1,
              color: Colors.grey.withValues(alpha: 0.3),
            ),
            AnimatedSocialStat(
              value: '${stats?.totalLessonsCompleted ?? 0}',
              label: 'Lessons',
              icon: Icons.menu_book,
              color: const Color(0xFF3B82F6),
            ),
            Container(
              height: 40,
              width: 1,
              color: Colors.grey.withValues(alpha: 0.3),
            ),
            AnimatedSocialStat(
              value: '${stats?.currentStreak ?? 0}',
              label: 'Day Streak',
              icon: Icons.local_fire_department,
              color: const Color(0xFFEF4444),
            ),
          ],
        );
      },
    );
  }

  IconData _getTierIcon(String tierCode) {
    switch (tierCode) {
      case 'A1':
        return Icons.eco;
      case 'A2':
        return Icons.spa;
      case 'B1':
        return Icons.bolt;
      case 'B2':
        return Icons.rocket_launch;
      case 'C1':
        return Icons.workspace_premium;
      case 'C2':
        return Icons.diamond;
      default:
        return Icons.star;
    }
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

        return GlassmorphicContainer(
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
              AnimatedProgressBar(
                progress: levelStatus.progressPercentage / 100,
                primaryColor: _getTierColor(currentTier.code),
                secondaryColor: _getTierColor(currentTier.code).withValues(alpha: 0.6),
                height: 12,
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
                GlassmorphicStatCard(
                  icon: Icons.local_fire_department,
                  color: Colors.orange,
                  title: 'Streak',
                  value: '$streak Days',
                  subtitle: streak > 0 ? 'Keep it up!' : 'Start today!',
                ),
                GlassmorphicStatCard(
                  icon: Icons.menu_book,
                  color: Colors.blue,
                  title: 'Lessons',
                  value: '$lessonsCompleted',
                  subtitle: 'Completed',
                ),
                GlassmorphicStatCard(
                  icon: Icons.school,
                  color: Colors.green,
                  title: 'Courses',
                  value: '$coursesCompleted',
                  subtitle: 'Finished',
                ),
                GlassmorphicStatCard(
                  icon: Icons.abc,
                  color: Colors.purple,
                  title: 'Vocabulary',
                  value: '$vocabularyMastered',
                  subtitle: 'Mastered',
                ),
                GlassmorphicStatCard(
                  icon: Icons.quiz,
                  color: Colors.teal,
                  title: 'Tests',
                  value: '$testsPassed',
                  subtitle: avgScore > 0 ? '${avgScore.toStringAsFixed(0)}% avg' : 'Passed',
                ),
                GlassmorphicStatCard(
                  icon: Icons.stars,
                  color: Colors.amber,
                  title: 'Badges',
                  value: '${stats?.totalCertificatesEarned ?? 0}',
                  subtitle: 'View all',
                  isAction: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AchievementsScreen()),
                    );
                  },
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
            GlassmorphicContainer(
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
                            // XP Chart with animated bars
                            SizedBox(
                              height: 120,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: activities.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final activity = entry.value;
                                  final maxXP = activities.map((a) => a.xpEarned).reduce((a, b) => a > b ? a : b);
                                  final normalizedValue = maxXP > 0 ? activity.xpEarned / maxXP : 0.0;
                                  final date = DateTime.parse(activity.date);
                                  final dayLabel = DateFormat('E').format(date).substring(0, 1);
                                  
                                  return Expanded(
                                    child: AnimatedActivityBar(
                                      label: dayLabel,
                                      value: normalizedValue,
                                      xpValue: activity.xpEarned,
                                      color: const Color(0xFF6366F1),
                                      delay: Duration(milliseconds: index * 100),
                                    ),
                                  );
                                }).toList(),
                              ),
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
