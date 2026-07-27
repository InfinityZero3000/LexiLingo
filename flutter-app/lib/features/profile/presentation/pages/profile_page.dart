import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/admin/admin_app.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/gamification/gamification.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/admin_panel_tile.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/learning_stats_section.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/level_progress_card.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/profile_header.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/quick_actions_row.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/recent_badges_section.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/weekly_activity_section.dart';
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
                    formatMemberSince(context, user?.createdAt),
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
            icon: Icon(Icons.science_rounded, color: accent),
            tooltip: 'practiceLab.shortTitle'.tr(),
            onPressed: () {
              Navigator.pushNamed(context, '/practice-lab');
            },
          ),
          IconButton(
            icon: Icon(Icons.workspace_premium_rounded, color: accent),
            tooltip: 'premium.title'.tr(),
            onPressed: () {
              Navigator.pushNamed(context, '/premium');
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                children: [
                  // Profile Header
                  ProfileHeader(user: user, onProfileEdited: _loadData),

                  // Quick Actions (Shop, Leaderboard, Social, Wallet)
                  const QuickActionsRow(),

                  // Level Progress Card
                  const ProfileLevelProgressCard(),

                  // AI Proficiency Assessment (radar chart)
                  const ProficiencyCard(),

                  // Learning Stats
                  const LearningStatsSection(),

                  // Weekly Activity
                  const WeeklyActivitySection(),

                  // Recent Badges
                  const RecentBadgesSection(),

                  // Admin Panel shortcut (only for authorised accounts)
                  if (_isAdminUser(user))
                    AdminPanelTile(onTap: _openAdminPanel),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
