import 'package:lexilingo_app/core/utils/freshness.dart';
import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/navigation/deferred_page.dart';
import 'package:lexilingo_app/features/admin/admin_app.dart'
    deferred as admin_app;
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
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class ProfilePage extends StatefulWidget {
  final bool isActive;

  const ProfilePage({super.key, this.isActive = true});

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

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final authProvider = context.read<AuthProvider>();
    final levelProvider = context.read<LevelProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final profileProvider = context.read<ProfileProvider>();
    final gamificationProvider = context.read<GamificationProvider>();
    final proficiencyProvider = context.read<ProficiencyProvider>();

    // Independent loads: one failing must not hold back the wallet or the rest.
    Future<void> guarded(Future<void> Function() load) async {
      try {
        await load();
      } catch (e) {
        debugPrint('Profile load step failed: $e');
      }
    }

    await Future.wait([
      guarded(gamificationProvider.loadWallet),
      guarded(() async {
        // Refresh the authoritative account state so email verification
        // changes show after returning from the email link.
        if (authProvider.currentUser != null) {
          await authProvider.refreshCurrentUser(maxAge: kPassiveReloadWindow);
          await levelProvider.fetchLevelFull(maxAge: kPassiveReloadWindow);
        }
      }),
      guarded(
        () => progressProvider.fetchMyProgress(maxAge: kPassiveReloadWindow),
      ),
      guarded(profileProvider.loadProfileData),
      guarded(proficiencyProvider.loadProfile),
    ]);
  }

  bool _isAdminUser(UserEntity? user) {
    return user?.canAccessAdminPanel ?? false;
  }

  void _openAdminPanel() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeferredPage(
          loadLibrary: admin_app.loadLibrary,
          builder: (_) => admin_app.AdminApp(),
        ),
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
      // "Member since" lives in the hero card, where it has the full width;
      // next to four actions it was being cut to "Member since Nov 2…".
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                Icons.person_rounded,
                color: Theme.of(context).colorScheme.surface,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'profile.title'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          // Wallet/Gems Button
          Consumer<GamificationProvider>(
            builder: (context, gamification, _) {
              final unavailable = gamification.walletUnavailable;
              return TapTarget(
                onTap: () => unavailable
                    ? gamification.loadWallet()
                    : Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      ),
                child: Container(
                  margin: const EdgeInsets.only(right: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.purpleGradient,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.diamond,
                        color: AppColors.surfaceLight,
                        size: 16,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Semantics(
                        label: gamification.wallet != null
                            ? null
                            : (unavailable
                                      ? 'errors.loadFailed'
                                      : 'common.loading')
                                  .tr(),
                        child: Text(
                          gamification.wallet?.gems.toString() ?? '—',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.surfaceLight,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
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
            tooltip: 'profile.settings'.tr(),
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
              color: Theme.of(context).colorScheme.error,

              tooltip: 'profile.adminMobile'.tr(),
              onPressed: _openAdminPanel,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
