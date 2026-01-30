import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lexilingo_app/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
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

    // Sync level with user XP
    if (authProvider.currentUser != null) {
      levelProvider.updateLevel(authProvider.currentUser!.xp);
    }

    // Load progress stats
    await progressProvider.fetchMyProgress();
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
            onPressed: () async {
               if (authProvider.isAuthenticated) {
                 await authProvider.signOut();
               } else {
                 await authProvider.signInWithGoogle();
               }
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
                      image: DecorationImage(
                        image: NetworkImage(user?.avatarUrl ??
                            'https://ui-avatars.com/api/?name=${Uri.encodeComponent(user?.displayName ?? 'User')}&background=random'),
                        fit: BoxFit.cover,
                      ),
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
    return Consumer<ProgressProvider>(
      builder: (context, progressProvider, child) {
        final summary = progressProvider.summary;
        final streak = user?.currentStreak ?? summary?.currentStreak ?? 0;
        final wordsLearned = summary?.lessonsCompleted ?? 0;
        final achievements = summary?.achievementsUnlocked ?? 0;

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
                  '$wordsLearned',
                  'Completed',
                ),
                Consumer<LevelProvider>(
                  builder: (context, levelProvider, child) {
                    final totalXp = levelProvider.levelStatus.totalXP;
                    return _buildStatCard(
                      context,
                      Icons.star,
                      Colors.purple,
                      'Total XP',
                      LevelCalculator.formatXP(totalXp),
                      'Experience',
                    );
                  },
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
                    '$achievements',
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

  Widget _buildWeeklyActivity(BuildContext context) {
    // TODO: Get real weekly activity data from ProgressProvider
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Weekly Activity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Activity Map',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildChartBar(context, 'M', 0.4),
              _buildChartBar(context, 'T', 0.6),
              _buildChartBar(context, 'W', 0.9),
              _buildChartBar(context, 'T', 0.5),
              _buildChartBar(context, 'F', 0.3),
              _buildChartBar(context, 'S', 0.2),
              _buildChartBar(context, 'S', 0.25),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentBadges(BuildContext context) {
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
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildBadgeItem(Icons.workspace_premium, Colors.orange, 'Early Bird'),
              const SizedBox(width: 16),
              _buildBadgeItem(Icons.forum, AppColors.primary, 'Chatterbox'),
              const SizedBox(width: 16),
              _buildBadgeItem(Icons.school, Colors.green, '100 Words'),
              const SizedBox(width: 16),
              _buildBadgeItem(Icons.lock, Colors.grey, 'Locked', isLocked: true),
            ],
          ),
        ),
      ],
    );
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

  Widget _buildChartBar(BuildContext context, String day, double pct) {
    return Column(
      children: [
         Container(
           width: 32,
           height: 80 * pct,
           decoration: BoxDecoration(
             color: AppColors.primary.withValues(alpha: 0.3 + (pct * 0.7)),
             borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
           ),
         ),
         const SizedBox(height: 8),
         Text(day, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
      ],
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

