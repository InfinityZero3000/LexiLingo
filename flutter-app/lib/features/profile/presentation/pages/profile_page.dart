import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:lexilingo_app/features/achievements/data/badge_asset_mapper.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:lexilingo_app/features/achievements/presentation/widgets/achievement_widgets.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/gamification/gamification.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/profile/presentation/pages/edit_profile_screen.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_ui_components.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/social/social.dart';
import 'package:lexilingo_app/features/user/presentation/pages/settings_page.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart'
    as glass;
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _badgeShineController;

  @override
  void initState() {
    super.initState();
    _badgeShineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _badgeShineController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final authProvider = context.read<AuthProvider>();
    final levelProvider = context.read<LevelProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final profileProvider = context.read<ProfileProvider>();
    final gamificationProvider = context.read<GamificationProvider>();
    final proficiencyProvider = context.read<ProficiencyProvider>();

    // Fetch authoritative level data from backend.
    // Falls back to local formula if network is unavailable.
    if (authProvider.currentUser != null) {
      await levelProvider.fetchLevelFull(sl<ApiClient>());
    }

    // Load progress stats
    await progressProvider.fetchMyProgress();

    // Load profile stats from backend
    await profileProvider.loadProfileData();

    // Load gamification data (wallet, etc.)
    await gamificationProvider.loadWallet();

    // Load proficiency data (AI-evaluated skill assessment)
    await proficiencyProvider.loadProfile();
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
        toolbarHeight: 86,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatMemberSince(user?.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ],
        ),
        automaticallyImplyLeading: false,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.purpleGradient,
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
          ),
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

              // AI Proficiency Assessment (radar chart)
              const ProficiencyCard(),

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
            color: AppColors.orange,
            gradient: AppColors.warmGradient,
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
            color: AppColors.greenSuccess,
            gradient: AppColors.successGradient,
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
            color: AppColors.primary,
            gradient: AppColors.indigoGradient,
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
            color: AppColors.purple,
            gradient: AppColors.purpleGradient,
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
        // Use numeric level progress, not CEFR-based
        final progress = levelProvider.displayLevelProgress;

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
                          AppColors.primary.withValues(alpha: 0.1),
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
                                AppColors.primary,
                                AppColors.purple,
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
                                      color: AppColors.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child:
                                      user?.avatarUrl != null &&
                                          user!.avatarUrl!.isNotEmpty
                                      ? Image.network(
                                          user.avatarUrl!,
                                          fit: BoxFit.cover,
                                          width: 120,
                                          height: 120,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.2),
                                                child: const Icon(
                                                  Icons.person,
                                                  size: 60,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                        )
                                      : Container(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.2,
                                          ),
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
                                      colors: [
                                        Color(0xFF137FEC),
                                        AppColors.primary,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.5,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.verified,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // User Name
                        Text(
                          user?.displayName ?? 'Guest User',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
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
                        // Level Badge + CEFR Proficiency Badge
                        Consumer<LevelProvider>(
                          builder: (_, lp, __) => Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              // Numeric Level badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: AppColors.primaryGradient,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.workspace_premium_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Level ${lp.displayLevel}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // CEFR Proficiency Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _getTierColor(
                                    lp.proficiencyLevel,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _getTierColor(
                                      lp.proficiencyLevel,
                                    ).withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _getTierIcon(lp.proficiencyLevel),
                                      size: 14,
                                      color: _getTierColor(lp.proficiencyLevel),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      lp.proficiencyLevel,
                                      style: TextStyle(
                                        color: _getTierColor(
                                          lp.proficiencyLevel,
                                        ),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '·',
                                      style: TextStyle(
                                        color: _getTierColor(
                                          lp.proficiencyLevel,
                                        ).withValues(alpha: 0.6),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      lp.proficiencyName,
                                      style: TextStyle(
                                        color: _getTierColor(
                                          lp.proficiencyLevel,
                                        ),
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
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
                        const SizedBox(height: 12),
                        // Edit Profile Button
                        GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EditProfileScreen(),
                              ),
                            );
                            if (result == true) {
                              _loadData(); // Refresh after edit
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: AppColors.primaryGradient,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit, color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'Edit Profile',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
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
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, _) {
        final stats = profileProvider.stats;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            AnimatedSocialStat(
              value: '${stats?.totalVocabularyMastered ?? 0}',
              label: 'Words',
              icon: Icons.spellcheck_rounded,
              color: AppColors.greenSuccessBright,
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
              color: AppColors.primary,
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
              color: AppColors.dangerGradient[0],
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
        final level = levelProvider.displayLevel;
        final xpIn = levelProvider.displayXpInLevel;
        final xpFor = levelProvider.displayXpForNextLevel;
        final progress = levelProvider.displayLevelProgress;

        return GlassmorphicContainer(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Level $level  →  Level ${level + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '$xpIn / $xpFor XP',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedProgressBar(
                progress: progress,
                primaryColor: AppColors.primaryGradient[0],
                secondaryColor: AppColors.primaryGradient[1],
                height: 12,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${xpFor - xpIn} XP to Level ${level + 1}',
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}% complete',
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
                  Icon(
                    Icons.insights_rounded,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.accentMint
                        : AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Learning Stats',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  GlassmorphicStatCard(
                    icon: Icons.local_fire_department,
                    color: AppColors.orange,
                    title: 'Streak',
                    value: '$streak',
                    subtitle: streak > 0 ? 'days in a row' : 'start today',
                    valueFontSize: 24,
                    iconBoxSize: 32,
                    iconSize: 16,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    middleSpacing: 8,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.abc,
                          color: AppColors.primary,
                          title: 'Lessons',
                          value: '$lessonsCompleted',
                          subtitle: 'completed',
                          valueFontSize: 22,
                          iconBoxSize: 30,
                          iconSize: 15,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          middleSpacing: 6,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.school,
                          color: AppColors.greenSuccess,
                          title: 'Courses',
                          value: '$coursesCompleted',
                          subtitle: 'finished',
                          valueFontSize: 22,
                          iconBoxSize: 30,
                          iconSize: 15,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          middleSpacing: 6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.auto_stories,
                          color: AppColors.purple,
                          title: 'Vocabulary',
                          value: '$vocabularyMastered',
                          subtitle: 'mastered',
                          valueFontSize: 22,
                          iconBoxSize: 30,
                          iconSize: 15,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          middleSpacing: 6,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.quiz,
                          color: AppColors.accentMint,
                          title: 'Tests',
                          value: '$testsPassed',
                          subtitle: avgScore > 0
                              ? '${avgScore.toStringAsFixed(0)}% avg'
                              : 'passed',
                          valueFontSize: 22,
                          iconBoxSize: 30,
                          iconSize: 15,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          middleSpacing: 6,
                        ),
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

  Widget _buildLoadingStats(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Learning Stats',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: List.generate(
            5,
            (index) => Container(
              decoration: BoxDecoration(
                color: AppColors.slate200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'Weekly Activity',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Last 7 Days',
                    style: TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
                              final maxXP = activities
                                  .map((a) => a.xpEarned)
                                  .reduce((a, b) => a > b ? a : b);
                              final normalizedValue = maxXP > 0
                                  ? activity.xpEarned / maxXP
                                  : 0.0;
                              final date = DateTime.parse(activity.date);
                              final dayLabel = DateFormat(
                                'E',
                              ).format(date).substring(0, 1);

                              return Expanded(
                                child: AnimatedActivityBar(
                                  label: dayLabel,
                                  value: normalizedValue,
                                  xpValue: activity.xpEarned,
                                  color: AppColors.primary,
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

  Widget _buildActivityStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildRecentBadges(BuildContext context) {
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
                    'Recent Badges',
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
                    child: const Text('View All'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 100,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
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

  bool _hasRenderableBadgeImage(UserAchievementEntity badge) {
    final achievement = badge.achievement;

    if (achievement.category.toLowerCase() == 'xp') {
      return false;
    }

    final networkBadge = achievement.badgeIcon?.trim();
    if (networkBadge != null && networkBadge.isNotEmpty) {
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
  Widget _buildBadgeItemFromEntity(UserAchievementEntity badge) {
    final achievement = badge.achievement;
    const badgeSize = 64.0;

    return Tooltip(
      message: '${achievement.name}\n${badge.unlockedTimeAgo}',
      child: Column(
        children: [
          SizedBox(
            width: badgeSize,
            height: badgeSize,
            child: AnimatedBuilder(
              animation: _badgeShineController,
              builder: (context, child) {
                final progress = _badgeShineController.value;
                // Perfect sweep from edge to edge (-1.5 to 1.5) with no pause at all
                final position = -1.5 + (progress * 3.0);

                return ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment(position - 0.5, -1.0),
                      end: Alignment(position + 0.5, 1.0),
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.1),
                        Colors.white.withValues(alpha: 0.7),
                        Colors.white.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
                    ).createShader(bounds);
                  },
                  child: child,
                );
              },
              child: AchievementBadge(
                achievement: achievement,
                isUnlocked: true,
                size: badgeSize,
              ),
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
}
