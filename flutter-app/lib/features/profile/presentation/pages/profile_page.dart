import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:ui';
import 'package:lexilingo_app/features/admin/admin_app.dart';
import 'package:lexilingo_app/features/achievements/data/badge_asset_mapper.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:lexilingo_app/features/achievements/presentation/widgets/achievement_widgets.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/gamification/gamification.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/profile/presentation/pages/edit_profile_screen.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_ui_components.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/screens/my_progress_screen.dart';
import 'package:lexilingo_app/features/social/social.dart';
import 'package:lexilingo_app/features/user/presentation/pages/settings_page.dart';
import 'package:lexilingo_app/features/voice/presentation/screens/voice_practice_screen.dart';
import 'package:lexilingo_app/features/profile/presentation/pages/learning_stats_pages.dart';
import 'package:lexilingo_app/features/user/domain/entities/weekly_activity_entity.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart'
    as glass;
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';

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
      duration: const Duration(milliseconds: 3000),
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
      await levelProvider.fetchLevelFull();
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

  bool _isAdminUser(UserEntity? user) {
    return user?.canAccessAdminPanel ?? false;
  }

  void _openAdminPanel() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AdminApp(),
        fullscreenDialog: true,
      ),
    );
  }

  String _formatMemberSince(BuildContext context, DateTime? createdAt) {
    if (createdAt == null) return 'profile.member'.tr();
    return 'profile.memberSince'.tr(
      namedArgs: {'date': DateFormat('MMM yyyy').format(createdAt)},
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 86,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.person_rounded,
                color: Theme.of(context).colorScheme.surface,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'profile.title'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatMemberSince(context, user?.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColorRoles.textSecondary(isDark),
                    ),
                  ),
                ],
              ),
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
                      Icon(
                        Icons.diamond,
                        color: Theme.of(context).colorScheme.surface,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${gamification.wallet?.gems ?? 0}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.surface,
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
            icon: Icon(Icons.mic_rounded, color: accent),
            tooltip: 'voice.pronunciation'.tr(),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VoicePracticeScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings, color: accent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
          if (_isAdminUser(user))
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_rounded),
              color: Colors.deepOrange,
              tooltip: 'Admin Mobile',
              onPressed: _openAdminPanel,
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

              // Admin Panel shortcut (only for authorised accounts)
              if (_isAdminUser(user)) _buildAdminPanelTile(context),

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
            label: 'profile.shop'.tr(),
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
            label: 'profile.ranks'.tr(),
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
            label: 'profile.friends'.tr(),
            color: AppColorRoles.primary(
              Theme.of(context).brightness == Brightness.dark,
            ),
            gradient: Theme.of(context).brightness == Brightness.dark
                ? AppColors.primaryGradientDark
                : AppColors.indigoGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SocialScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _buildQuickActionButton(
            context,
            icon: Icons.insights_rounded,
            label: 'profile.progress'.tr(),
            color: AppColors.purple,
            gradient: AppColors.purpleGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyProgressScreen()),
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
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.surface,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.surface,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
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
                          (isDark ? accent : AppColors.primary).withValues(
                            alpha: 0.15,
                          ),
                          (isDark ? accent : AppColors.primary).withValues(
                            alpha: 0.1,
                          ),
                          AppColors.surfaceLight.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? accent : AppColors.primary)
                              .withValues(alpha: 0.12),
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
                              gradientColors: [
                                isDark ? accent : AppColors.primary,
                                isDark ? accent : AppColors.primary,
                                AppColors.purple,
                              ],
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.surface
                                        .withValues(alpha: 0.5),
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (isDark ? accent : AppColors.primary)
                                              .withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: NetworkAvatarImage(
                                    imageUrl: user?.avatarUrl,
                                    fit: BoxFit.cover,
                                    width: 120,
                                    height: 120,
                                    fallback: Container(
                                      color:
                                          (isDark ? accent : AppColors.primary)
                                              .withValues(alpha: 0.2),
                                      child: Icon(
                                        Icons.person,
                                        size: 60,
                                        color: isDark
                                            ? accent
                                            : AppColors.primary,
                                      ),
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
                                    gradient: LinearGradient(
                                      colors: [
                                        isDark ? accent : AppColors.primary,
                                        isDark ? accent : AppColors.primary,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.surfaceLight,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            (isDark
                                                    ? accent
                                                    : AppColors.primary)
                                                .withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.verified,
                                    color: AppColors.surfaceLight,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // User Name
                        Text(
                          user?.displayName ?? 'profile.guestUser'.tr(),
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
                            style: const TextStyle(
                              color: AppColors.grey600,
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Level Badge + CEFR Proficiency Badge + Rank Badge
                        Consumer<LevelProvider>(
                          builder: (_, lp, __) {
                            final rankData = rankVisualDataFor(lp.rank);
                            final isMasterRank = lp.rank == 'master';
                            return Wrap(
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
                                    gradient: LinearGradient(
                                      colors: AppColorRoles.primaryGradient(
                                        isDark,
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (isDark
                                                ? accent
                                                : AppColors.primary)
                                            .withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.workspace_premium_rounded,
                                        color: AppColors.surfaceLight,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'profile.level'.tr(
                                          namedArgs: {
                                            'level': '${lp.displayLevel}',
                                          },
                                        ),
                                        style: TextStyle(
                                          color: AppColors.surfaceLight,
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
                                        color: _getTierColor(
                                          lp.proficiencyLevel,
                                        ),
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
                                // League Rank Badge
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const LeaderboardScreen(),
                                    ),
                                  ),
                                  child: isMasterRank
                                      ? ShaderMask(
                                          shaderCallback: (bounds) =>
                                              const LinearGradient(
                                                colors: [
                                                  Color(0xFF5AB6FF),
                                                  Color(0xFFFFD64F),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ).createShader(bounds),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.4,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                RankAssetIcon(
                                                  rank: lp.rank,
                                                  size: 16,
                                                  decorated: false,
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  lp.rankName,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: rankData.color.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: rankData.color.withValues(
                                                alpha: 0.4,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              RankAssetIcon(
                                                rank: lp.rank,
                                                size: 16,
                                                decorated: false,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                lp.rankName,
                                                style: TextStyle(
                                                  color: rankData.color,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        // Member Since
                        Text(
                          _formatMemberSince(context, user?.createdAt),
                          style: const TextStyle(
                            color: AppColors.grey600,
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
                              gradient: LinearGradient(
                                colors: AppColorRoles.primaryGradient(isDark),
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: (isDark ? accent : AppColors.primary)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.edit,
                                  color: AppColors.surfaceLight,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'profile.editProfile'.tr(),
                                  style: TextStyle(
                                    color: AppColors.surfaceLight,
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
              label: 'profile.words'.tr(),
              icon: Icons.spellcheck_rounded,
              color: AppColors.greenSuccessBright,
            ),
            Container(
              height: 40,
              width: 1,
              color: AppColors.grey400.withValues(alpha: 0.5),
            ),
            AnimatedSocialStat(
              value: '${stats?.totalLessonsCompleted ?? 0}',
              label: 'profile.lessons'.tr(),
              icon: Icons.menu_book,
              color: AppColorRoles.primary(
                Theme.of(context).brightness == Brightness.dark,
              ),
            ),
            Container(
              height: 40,
              width: 1,
              color: AppColors.grey400.withValues(alpha: 0.5),
            ),
            AnimatedSocialStat(
              value: '${stats?.currentStreak ?? 0}',
              label: 'profile.dayStreak'.tr(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    'profile.levelRange'.tr(
                      namedArgs: {
                        'level': '$level',
                        'nextLevel': '${level + 1}',
                      },
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'profile.xpProgress'.tr(
                      namedArgs: {'current': '$xpIn', 'total': '$xpFor'},
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColorRoles.primary(
                    isDark,
                  ).withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColorRoles.primary(isDark),
                  ),
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'profile.xpToNextLevel'.tr(
                      namedArgs: {
                        'xp': '${xpFor - xpIn}',
                        'level': '${level + 1}',
                      },
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'profile.percentComplete'.tr(
                      namedArgs: {
                        'percent': (progress * 100).toStringAsFixed(0),
                      },
                    ),
                    style: TextStyle(
                      color: AppColorRoles.primary(isDark),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tierCode) {
      case 'A1':
        return AppColors.greenSuccessBright;
      case 'A2':
        return AppColors.teal;
      case 'B1':
        return AppColorRoles.primary(isDark);
      case 'B2':
        return AppColorRoles.primaryDeep(isDark);
      case 'C1':
        return AppColors.purple;
      case 'C2':
        return AppColors.warning;
      default:
        return AppColorRoles.primary(isDark);
    }
  }

  Widget _buildLearningStats(BuildContext context, dynamic user) {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primaryColor = AppColorRoles.primary(isDark);
        // Use stats from ProfileProvider (backend API)
        final stats = profileProvider.stats;
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
                  Icon(Icons.insights_rounded, color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'profile.learningStats'.tr(),
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
                  Row(
                    children: [
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.abc,
                          color: primaryColor,
                          title: 'profile.lessons'.tr(),
                          value: '$lessonsCompleted',
                          subtitle: 'profile.completed'.tr(),
                          valueInRightCircle: true,
                          valueCircleSize: 40,
                          valueCircleFontSize: 18,
                          isAction: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearningLessonsStatsPage(),
                            ),
                          ),
                          iconBoxSize: 28,
                          iconSize: 14,
                          titleFontSize: 13,
                          subtitleFontSize: 11,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.school,
                          color: primaryColor,
                          title: 'profile.courses'.tr(),
                          value: '$coursesCompleted',
                          subtitle: 'profile.finished'.tr(),
                          valueInRightCircle: true,
                          valueCircleSize: 40,
                          valueCircleFontSize: 18,
                          isAction: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearningCoursesStatsPage(),
                            ),
                          ),
                          iconBoxSize: 28,
                          iconSize: 14,
                          titleFontSize: 13,
                          subtitleFontSize: 11,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
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
                          color: primaryColor,
                          title: 'profile.vocabulary'.tr(),
                          value: '$vocabularyMastered',
                          subtitle: 'profile.mastered'.tr(),
                          valueInRightCircle: true,
                          valueCircleSize: 40,
                          valueCircleFontSize: 18,
                          isAction: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const LearningVocabularyStatsPage(),
                            ),
                          ),
                          iconBoxSize: 28,
                          iconSize: 14,
                          titleFontSize: 13,
                          subtitleFontSize: 11,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassmorphicStatCard(
                          icon: Icons.quiz,
                          color: primaryColor,
                          title: 'profile.tests'.tr(),
                          value: '$testsPassed',
                          subtitle: avgScore > 0
                              ? 'profile.averagePercent'.tr(
                                  namedArgs: {
                                    'percent': avgScore.toStringAsFixed(0),
                                  },
                                )
                              : 'profile.passed'.tr(),
                          valueInRightCircle: true,
                          valueCircleSize: 40,
                          valueCircleFontSize: 18,
                          isAction: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LearningTestsStatsPage(),
                            ),
                          ),
                          iconBoxSize: 28,
                          iconSize: 14,
                          titleFontSize: 13,
                          subtitleFontSize: 11,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
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
            'profile.learningStats'.tr(),
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
            4,
            (index) => ShimmerContainer(
              child: SkeletonBox(height: double.infinity, borderRadius: 12),
            ),
          ),
        ),
      ],
    );
  }

  void _showWeeklyActivityDetail(
    BuildContext context,
    List<WeeklyActivityEntity> activities,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WeeklyActivityDetailSheet(activities: activities),
    );
  }

  Widget _buildWeeklyActivity(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final activities = profileProvider.weeklyActivity;
        final isLoading = profileProvider.isLoadingActivity;
        final activityError = profileProvider.activityError;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'profile.weeklyActivity'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    onTap: activities.isNotEmpty
                        ? () => _showWeeklyActivityDetail(context, activities)
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'profile.last7Days'.tr(),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (activities.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            GlassmorphicContainer(
              child: isLoading && activities.isEmpty
                  ? SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: ShimmerContainer(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 120,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(
                                    7,
                                    (index) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: SkeletonBox(
                                          height: 20.0 + (index % 3) * 30.0,
                                          borderRadius: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: List.generate(
                                  7,
                                  (index) => const Expanded(
                                    child: Center(
                                      child: SkeletonBox(
                                        width: 20,
                                        height: 12,
                                        borderRadius: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: List.generate(
                                  3,
                                  (index) => const Column(
                                    children: [
                                      SkeletonCircle(size: 20),
                                      SizedBox(height: 4),
                                      SkeletonBox(
                                        width: 40,
                                        height: 16,
                                        borderRadius: 4,
                                      ),
                                      SizedBox(height: 4),
                                      SkeletonBox(
                                        width: 60,
                                        height: 12,
                                        borderRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : activities.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          activityError == null || activityError.isEmpty
                              ? 'profile.noActivityDataYet'.tr()
                              : activityError,
                          style: const TextStyle(color: AppColors.grey600),
                          textAlign: TextAlign.center,
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

                              return Expanded(
                                child: AnimatedActivityBar(
                                  label: '',
                                  value: normalizedValue,
                                  xpValue: activity.xpEarned,
                                  color: AppColorRoles.primary(isDark),
                                  delay: Duration(milliseconds: index * 100),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        // Day labels row — separate from bars to ensure alignment
                        const SizedBox(height: 6),
                        Row(
                          children: activities.map((activity) {
                            String dayLabel;
                            final parsedDate = DateTime.tryParse(activity.date);
                            if (parsedDate != null) {
                              dayLabel = DateFormat(
                                'E',
                              ).format(parsedDate).substring(0, 1);
                            } else {
                              final raw = activity.date.trim();
                              dayLabel = raw.isEmpty
                                  ? '-'
                                  : raw.substring(0, 1).toUpperCase();
                            }
                            return Expanded(
                              child: Center(
                                child: Text(
                                  dayLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? AppColors.grey500
                                        : AppColors.grey600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        // Summary stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildActivityStat(
                              'profile.totalXp'.tr(),
                              '${activities.fold<int>(0, (sum, a) => sum + a.xpEarned)}',
                              Icons.star,
                              AppColors.warning,
                            ),
                            _buildActivityStat(
                              'profile.lessons'.tr(),
                              '${activities.fold<int>(0, (sum, a) => sum + a.lessonsCompleted)}',
                              Icons.menu_book,
                              AppColorRoles.primary(isDark),
                            ),
                            _buildActivityStat(
                              'profile.words'.tr(),
                              '${activities.fold<int>(0, (sum, a) => sum + a.vocabularyLearned)}',
                              Icons.abc,
                              AppColors.greenSuccessBright,
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
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.grey600),
        ),
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

  Widget _buildAdminPanelTile(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openAdminPanel,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFF3B00)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepOrange.withValues(alpha: isDark ? 0.4 : 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Switch to Admin Panel',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'LexiLingo Admin mobile',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.open_in_new_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeeklyActivityDetailSheet extends StatelessWidget {
  final List<WeeklyActivityEntity> activities;

  const _WeeklyActivityDetailSheet({required this.activities});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColorRoles.primary(isDark);

    final totalXP = activities.fold<int>(0, (s, a) => s + a.xpEarned);
    final totalLessons = activities.fold<int>(
      0,
      (s, a) => s + a.lessonsCompleted,
    );
    final totalWords = activities.fold<int>(
      0,
      (s, a) => s + a.vocabularyLearned,
    );
    final maxXP = activities
        .map((a) => a.xpEarned)
        .reduce((a, b) => a > b ? a : b);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'profile.weeklyActivity'.tr(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'profile.last7DaysDetailedBreakdown'.tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              // Summary row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _SummaryChip(
                      icon: Icons.star,
                      color: AppColors.warning,
                      label: 'profile.xpValue'.tr(
                        namedArgs: {'xp': '$totalXP'},
                      ),
                      sublabel: 'profile.total'.tr(),
                    ),
                    const SizedBox(width: 8),
                    _SummaryChip(
                      icon: Icons.menu_book,
                      color: primary,
                      label: '$totalLessons',
                      sublabel: 'profile.lessons'.tr(),
                    ),
                    const SizedBox(width: 8),
                    _SummaryChip(
                      icon: Icons.abc,
                      color: AppColors.greenSuccessBright,
                      label: '$totalWords',
                      sublabel: 'profile.words'.tr(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Day list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: activities.length,
                  itemBuilder: (context, index) {
                    final a = activities[index];
                    final isBest = a.xpEarned == maxXP && maxXP > 0;
                    final barFraction = maxXP > 0 ? a.xpEarned / maxXP : 0.0;

                    DateTime? parsedDate = DateTime.tryParse(a.date);
                    final String dayName = parsedDate != null
                        ? DateFormat('EEEE').format(parsedDate)
                        : a.date;
                    final String shortDate = parsedDate != null
                        ? DateFormat('MMM d').format(parsedDate)
                        : '';

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isBest
                            ? primary.withValues(alpha: isDark ? 0.15 : 0.08)
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.03)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isBest
                              ? primary.withValues(alpha: 0.4)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(
                                      dayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (shortDate.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        shortDate,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isBest)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.warning.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.emoji_events,
                                        size: 12,
                                        color: AppColors.warning,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'profile.bestDay'.tr(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // XP bar
                          if (a.xpEarned > 0) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: barFraction,
                                      backgroundColor: primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        primary,
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'profile.xpValue'.tr(
                                    namedArgs: {'xp': '${a.xpEarned}'},
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                          // Stats chips
                          Row(
                            children: [
                              if (a.xpEarned == 0)
                                Text(
                                  'profile.noActivity'.tr(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                )
                              else ...[
                                _MiniStat(
                                  icon: Icons.menu_book,
                                  color: primary,
                                  value: 'profile.lessonsCount'.tr(
                                    namedArgs: {
                                      'count': '${a.lessonsCompleted}',
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _MiniStat(
                                  icon: Icons.abc,
                                  color: AppColors.greenSuccessBright,
                                  value: 'profile.wordsCount'.tr(
                                    namedArgs: {
                                      'count': '${a.vocabularyLearned}',
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Bottom safe area
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sublabel;

  const _SummaryChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;

  const _MiniStat({
    required this.icon,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
