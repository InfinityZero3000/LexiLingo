import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart'
    as glass;
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_thumbnail_resolver.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/pages/vocab_library_page.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/daily_review_card.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/points_calendar_dialog.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_challenges_widget.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_reward_dialog.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/level_up_dialog.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_up_dialog.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';
import 'package:lexilingo_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';

class HomePageNew extends StatefulWidget {
  const HomePageNew({super.key});

  @override
  State<HomePageNew> createState() => _HomePageNewState();
}

class _HomePageNewState extends State<HomePageNew> {
  LevelProvider? _levelProvider;
  StreakProvider? _streakProvider;
  bool _isDailyRewardDialogShowing = false;

  @override
  void initState() {
    super.initState();
    // Load home data after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeProvider = context.read<HomeProvider>();
      // Capture LevelProvider reference HERE (synchronously), before any
      // async gap, and store as a field so dispose() can safely remove the
      // listener without touching context.
      _levelProvider = context.read<LevelProvider>();
      homeProvider.loadHomeData().then((_) {
        // Fetch authoritative level data from backend.
        // Falls back to local formula if network is unavailable.
        if (mounted) _levelProvider?.fetchLevelFull(sl<ApiClient>());
      });
      // Listen for level-up events triggered by fetchLevelFull
      _levelProvider?.addListener(_onLevelProviderChange);
      
      // Setup streak provider listener
      _streakProvider = context.read<StreakProvider>();
      _streakProvider?.addListener(_onStreakProviderChange);
      
      // Load streak data here (after auth token is ready) instead of relying
      // on the race-prone call in main.dart that fires before authentication.
      _streakProvider?.loadStreak();
    });
  }

  @override
  void dispose() {
    _levelProvider?.removeListener(_onLevelProviderChange);
    _streakProvider?.removeListener(_onStreakProviderChange);
    super.dispose();
  }

  void _onStreakProviderChange() {
    final streakProvider = _streakProvider;
    if (streakProvider == null || !mounted) {
      return;
    }

    final streak = streakProvider.streak;
    if (streak != null && streak.isDailyRewardAvailable && !_isDailyRewardDialogShowing) {
      _isDailyRewardDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDailyRewardDialog(context, streakProvider).then((_) {
          _isDailyRewardDialogShowing = false;
        });
      });
    }
  }

  /// Shows the Level-Up or Rank-Up celebration dialog when the provider signals it.
  void _onLevelProviderChange() {
    final levelProvider = _levelProvider;
    if (levelProvider == null || !mounted) {
      return;
    }

    if (levelProvider.showLevelUpDialog) {
      levelProvider.dismissLevelUpDialog();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        LevelUpDialog.show(
          context,
          newLevel: levelProvider.displayLevel,
          xpAwarded: levelProvider.displayXpForNextLevel,
        );
      });
    }

    if (levelProvider.showRankUpDialog) {
      final oldRank = levelProvider.previousRank;
      levelProvider.dismissRankUpDialog();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Need to import RankUpDialog, though it seems it should be in gamification
        if (!mounted || oldRank == null) return;
        RankUpDialog.show(
          context,
          newRank: levelProvider.rank,
          oldRank: oldRank,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Consumer3<HomeProvider, UserProvider, AuthProvider>(
          builder: (context, homeProvider, userProvider, authProvider, child) {
            if (homeProvider.isLoading &&
                homeProvider.featuredCourses.isEmpty) {
              return _buildSkeletonLoading();
            }

            if (homeProvider.errorMessage != null) {
              return ErrorDisplayWidget.fromMessage(
                message: homeProvider.errorMessage!,
                onRetry: () => homeProvider.loadHomeData(),
              );
            }

            return RefreshIndicator(
              onRefresh: () => Future.wait([
                homeProvider.refreshData(),
                context.read<StreakProvider>().loadStreak(),
              ]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24.0),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildHeader(context, homeProvider, authProvider),
                  ),
                  const SizedBox(height: 12),
                  _buildStreakCard(context, homeProvider),
                  const SizedBox(height: 12),
                  _buildSectionTitle(context, 'home.quickActions'.tr()),
                  const SizedBox(height: 8),
                  _buildQuickActionsHorizontal(context),
                  const SizedBox(height: 12),
                  _buildLevelAndDailyGoalRow(context, homeProvider),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: DailyChallengesCard(),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: DailyReviewCard(),
                  ),
                  const SizedBox(height: 12),
                  _buildSectionTitle(
                    context,
                    'home.continueLearningSection'.tr(),
                  ),
                  const SizedBox(height: 8),
                  _buildEnrolledCoursesSection(context, homeProvider),
                  const SizedBox(height: 12),
                  _buildSectionTitle(context, 'home.featuredCourses'.tr()),
                  const SizedBox(height: 8),
                  _buildFeaturedCourses(context, homeProvider),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    HomeProvider homeProvider,
    AuthProvider authProvider,
  ) {
    // Get user display name from AuthProvider
    final user = authProvider.currentUser;
    final displayName = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : user?.username ?? 'profile.guestUser'.tr();

    return Consumer2<NotificationProvider, LevelProvider>(
      builder: (context, notificationProvider, levelProvider, child) {
        final totalXP = levelProvider.levelStatus.totalXP;
        return PersonalizedGreetingHeader(
          userName: displayName,
          totalXP: totalXP,
          avatarUrl: user?.avatarUrl,
          notificationCount: notificationProvider.unreadCount,
          onNotificationTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
          },
          onAvatarTap: () {
            // Navigate to profile or settings
          },
        );
      },
    );
  }

  Widget _buildStreakCard(BuildContext context, HomeProvider provider) {
    return Consumer<StreakProvider>(
      builder: (context, streakProvider, child) {
        final streak = streakProvider.streak;
        final currentStreak = streak?.currentStreak ?? provider.streakDays;
        final longestStreak = streak?.longestStreak ?? 0;
        final isActiveToday = streak?.isActiveToday ?? false;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: AnimatedStreakCard(
            streakDays: currentStreak,
            longestStreak: longestStreak,
            isActiveToday: isActiveToday,
            weeklyActivity: streak?.weeklyActivity,
            weeklyProgressPercentages: provider.weeklyProgress.weekProgress
                .map((day) => day.progressPercentage)
                .toList(growable: false),
            onTap: () {
              if (streak != null) {
                showPointsCalendarDialog(context, streak);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildLevelAndDailyGoalRow(
    BuildContext context,
    HomeProvider provider,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;

          if (isNarrow) {
            return Column(
              children: [
                SizedBox(height: 148, child: LevelProgressCard(compact: true)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 148,
                  child: _buildDailyGoalCard(
                    context,
                    provider,
                    compact: true,
                    margin: EdgeInsets.zero,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: SizedBox(
                  height: 148,
                  child: LevelProgressCard(compact: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 148,
                  child: _buildDailyGoalCard(
                    context,
                    provider,
                    compact: true,
                    margin: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDailyGoalCard(
    BuildContext context,
    HomeProvider provider, {
    bool compact = false,
    EdgeInsetsGeometry? margin,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use user-configured daily goal from settings; fall back to HomeProvider.
    final goalXP = context.read<SettingsProvider>().dailyGoalXP;
    final earnedXP = provider.dailyXP;
    final percentage = goalXP > 0 ? (earnedXP / goalXP).clamp(0.0, 1.0) : 0.0;
    final isCompleted = percentage >= 1.0;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = AppColorRoles.primary(isDark);
    final accentDeep = AppColorRoles.primaryDeep(isDark);
    final surfaceBg = colorScheme.surfaceContainerHighest;
    final compactBg = isCompleted
        ? AppColors.greenSuccessBright.withValues(alpha: 0.10)
        : accent.withValues(alpha: 0.07);
    final cardPadding = compact ? 14.0 : 20.0;
    final ringSize = compact ? 58.0 : 70.0;
    final ringStroke = compact ? 5.0 : 6.0;
    final titleFontSize = compact ? 16.0 : null;
    final valueFontSize = compact ? 18.0 : null;
    final chipFontSize = compact ? 11.0 : 12.0;
    final badgeIconSize = compact ? 16.0 : 18.0;
    final ringValueFontSize = compact ? 12.0 : 14.0;

    final borderRadius = BorderRadius.circular(compact ? 16 : 20);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: margin ?? const EdgeInsets.symmetric(horizontal: 16),
        child: InkWell(
          onTap: () => _showDailyGoalSheet(context, provider),
          borderRadius: borderRadius,
          child: Ink(
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: compact ? compactBg : surfaceBg,
              borderRadius: borderRadius,
              border: Border.all(
                color: isCompleted
                    ? AppColors.greenSuccessBright.withValues(alpha: 0.3)
                    : accent.withValues(alpha: 0.35),
              ),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isCompleted ? Icons.emoji_events : Icons.bolt,
                              color: isCompleted
                                  ? AppColors.greenSuccessBright
                                  : accent,
                              size: badgeIconSize,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'home.dailyGoal'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isCompleted
                                        ? AppColors.greenSuccess
                                        : accentDeep,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.surface,
                            ),
                            child: glass.AnimatedProgressRing(
                              progress: percentage.clamp(0.0, 1.0),
                              size: ringSize + 10,
                              strokeWidth: ringStroke,
                              gradientColors: isCompleted
                                  ? const [
                                      AppColors.greenSuccessBright,
                                      AppColors.greenSuccess,
                                    ]
                                  : AppColorRoles.primaryGradient(isDark),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isCompleted)
                                    const Icon(
                                      Icons.check,
                                      color: AppColors.greenSuccessBright,
                                      size: 18,
                                    )
                                  else
                                    Text(
                                      '${(percentage * 100).toInt()}%',
                                      style: TextStyle(
                                        fontSize: ringValueFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: accent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$earnedXP/$goalXP XP',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isCompleted
                                  ? AppColors.greenSuccessBright
                                  : accent,
                            ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      // Animated Progress Ring
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.surface,
                        ),
                        child: glass.AnimatedProgressRing(
                          progress: percentage.clamp(0.0, 1.0),
                          size: ringSize,
                          strokeWidth: ringStroke,
                          gradientColors: isCompleted
                              ? const [
                                  AppColors.greenSuccessBright,
                                  AppColors.greenSuccess,
                                ]
                              : const [AppColors.primary, AppColors.primary],
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCompleted)
                                const Icon(
                                  Icons.check,
                                  color: AppColors.greenSuccessBright,
                                  size: 20,
                                )
                              else
                                Text(
                                  '${(percentage * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: ringValueFontSize,
                                    fontWeight: FontWeight.bold,
                                    color: isCompleted
                                        ? AppColors.greenSuccessBright
                                        : AppColors.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 12 : 20),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(compact ? 5 : 6),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isCompleted
                                        ? Icons.emoji_events
                                        : Icons.bolt,
                                    color: isCompleted
                                        ? AppColors.greenSuccessBright
                                        : accent,
                                    size: badgeIconSize,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'home.dailyXpGoal'.tr(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: titleFontSize,
                                          color: isCompleted
                                              ? AppColors.greenSuccess
                                              : accentDeep,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 6 : 8),
                            Text(
                              '$earnedXP/$goalXP XP',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: valueFontSize,
                                    color: isCompleted
                                        ? AppColors.greenSuccessBright
                                        : accent,
                                  ),
                            ),
                            SizedBox(height: compact ? 2 : 4),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 8 : 10,
                                vertical: compact ? 3 : 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isCompleted
                                        ? Icons.celebration
                                        : Icons.trending_up,
                                    size: 14,
                                    color: isCompleted
                                        ? AppColors.greenSuccessBright
                                        : accent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isCompleted
                                        ? 'home.goalCompleted'.tr()
                                        : 'home.keepGoing'.tr(),
                                    style: TextStyle(
                                      fontSize: chipFontSize,
                                      fontWeight: FontWeight.w600,
                                      color: isCompleted
                                          ? AppColors.greenSuccessBright
                                          : accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDailyGoalSheet(
    BuildContext context,
    HomeProvider homeProvider,
  ) async {
    final settings = context.read<SettingsProvider>();
    final settingsState = settings.settings;

    if (settingsState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('home.dailyGoalSettingsPending'.tr())),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final primaryColor = AppColorRoles.primary(isDark);

        return Consumer<SettingsProvider>(
          builder: (sheetContext, settingsProvider, _) {
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Text(
                      'home.dailyGoal'.tr(),
                      style: Theme.of(sheetContext).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'home.dailyGoalDescription'.tr(),
                      style: Theme.of(sheetContext).textTheme.bodyMedium
                          ?.copyWith(color: AppColorRoles.textMuted(isDark)),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryColor,
                            primaryColor.withValues(alpha: 0.72),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${homeProvider.dailyXP}/${settingsProvider.dailyGoalXP} XP',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'settings.goal_progress'.tr(
                              namedArgs: {
                                'percent':
                                    '${(homeProvider.dailyProgressPercentage * 100).toInt()}',
                              },
                            ),
                            style: Theme.of(sheetContext).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onPrimary.withValues(
                                    alpha: 0.88,
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...SettingsProvider.dailyGoalPresets.map((goal) {
                      final xp = goal['xp'] as int;
                      final isSelected = settingsProvider.dailyGoalXP == xp;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            await settingsProvider.updateDailyGoal(xp);
                            if (!sheetContext.mounted) return;

                            if (settingsProvider.error == null) {
                              homeProvider.updateDailyGoalTarget(xp);
                              Navigator.of(sheetContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'settings.goal_updated'.tr(
                                      namedArgs: {'xp': '$xp'},
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text(settingsProvider.error!),
                                ),
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primaryColor.withValues(alpha: 0.12)
                                  : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : colorScheme.outlineVariant,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? primaryColor
                                        : primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    goal['icon'] as IconData,
                                    color: isSelected
                                        ? colorScheme.onPrimary
                                        : primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${(goal['label'] as String).tr()} • $xp XP',
                                        style: Theme.of(sheetContext)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (goal['description'] as String).tr(),
                                        style: Theme.of(sheetContext)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppColorRoles.textMuted(
                                                isDark,
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check_circle, color: primaryColor),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEnrolledCoursesSection(
    BuildContext context,
    HomeProvider provider,
  ) {
    // Show loading state if courses are being loaded
    if (provider.isLoading && provider.enrolledCourses.isEmpty) {
      return SizedBox(
        height: 126, // Slightly increased to match card content height
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 2,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(right: 16),
              width: 240, // Reduced from 296 roughly
              child: const CardSkeleton(isHorizontal: true),
            );
          },
        ),
      );
    }

    // Show empty state if no enrolled courses
    if (provider.enrolledCourses.isEmpty) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDarkMuted : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.slate200,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.school_outlined,
                size: 48,
                color: isDark ? AppColors.textMuted : AppColors.textGrey,
              ),
              const SizedBox(height: 12),
              Text(
                'home.noEnrolledCoursesYet'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textInverted : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'home.enrollCoursePrompt'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.textMuted : AppColors.textGrey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Show enrolled courses
    return _buildEnrolledCourses(context, provider);
  }

  Widget _buildEnrolledCourses(BuildContext context, HomeProvider provider) {
    return SizedBox(
      height: 136,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: provider.enrolledCourses.length,
        itemBuilder: (context, index) {
          final course = provider.enrolledCourses[index];
          // Staggered animation for enrolled courses
          return AnimatedListItem(
            index: index,
            duration: const Duration(milliseconds: 300),
            delayPerItem: const Duration(milliseconds: 80),
            child: _buildEnrolledCourseCard(context, course),
          );
        },
      ),
    );
  }

  Widget _buildEnrolledCourseCard(BuildContext context, CourseEntity course) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = course.userProgress ?? 0;
    final progressColor = progress >= 80
        ? AppColors.greenSuccessBright
        : progress >= 50
        ? AppColors.orange
        : AppColorRoles.primary(isDark);
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceBg = colorScheme.surfaceContainerHighest;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(courseId: course.id),
          ),
        );
      },
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: surfaceBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: progressColor.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Course thumbnail
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colorScheme.surface,
                  image: course.thumbnailUrl != null
                      ? DecorationImage(
                          image: NetworkImage(course.thumbnailUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: course.thumbnailUrl == null
                    ? Icon(Icons.school, size: 32, color: progressColor)
                    : null,
              ),
              const SizedBox(width: 16),
              // Info section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      course.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: progressColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _localizedCourseLevel(course.level),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: progressColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'profile.lessonsCount'.tr(
                            namedArgs: {'count': '${course.totalLessons}'},
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColorRoles.textSecondary(isDark),
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Progress bar
                    Stack(
                      children: [
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: progressColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress / 100,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  progressColor,
                                  progressColor.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${progress.toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: progressColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                progressColor,
                                progressColor.withValues(alpha: 0.8),
                              ],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 16,
                            color: AppColors.surfaceLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedCourses(BuildContext context, HomeProvider provider) {
    // Show skeleton loading while courses are loading
    if (provider.isLoading && provider.featuredCourses.isEmpty) {
      return SizedBox(
        height: 220,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 3,
          itemBuilder: (context, index) {
            return Container(
              width: 240,
              margin: const EdgeInsets.only(right: 16),
              child: const CardSkeleton(isHorizontal: false),
            );
          },
        ),
      );
    }

    if (provider.featuredCourses.isEmpty) {
      return _buildFeaturedCoursesEmptyState(context, provider);
    }

    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: provider.featuredCourses.length,
        itemBuilder: (context, index) {
          final course = provider.featuredCourses[index];
          // Staggered animation for featured courses
          return AnimatedListItem(
            index: index,
            duration: const Duration(milliseconds: 400),
            delayPerItem: const Duration(milliseconds: 100),
            beginOffset: const Offset(0, 60),
            child: _buildCourseCard(context, course, provider),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedCoursesEmptyState(
    BuildContext context,
    HomeProvider provider,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColorRoles.primary(isDark);

    return SizedBox(
      height: 220,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: primary.withValues(alpha: isDark ? 0.22 : 0.16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.auto_stories_rounded, color: primary, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              'home.noFeaturedCourses'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'home.noFeaturedCoursesDescription'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColorRoles.textMuted(isDark),
                height: 1.35,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => provider.loadFeaturedCourses(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('home.reload'.tr()),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => provider.refreshData(),
                  child: Text('home.refreshData'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseCard(
    BuildContext context,
    CourseEntity course,
    HomeProvider provider,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final levelColor = _getLevelColor(course.level, isDark: isDark);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CourseDetailScreen(
              courseId: course.id,
              heroTag: 'featured-course-image-${course.id}',
              initialThumbnailUrl: course.thumbnailUrl,
              fallbackThumbnailUrl: courseFallbackThumbnailUrl(course),
            ),
          ),
        );
      },
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : levelColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero animation for course thumbnail
            Hero(
              tag: 'featured-course-image-${course.id}',
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildFeaturedCourseThumbnail(
                        context,
                        course,
                        levelColor,
                      ),
                    ),
                    // Gradient overlay
                    Container(
                      height: 110,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                    // Level badge - top left
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              levelColor,
                              levelColor.withValues(alpha: 0.85),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: levelColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          _localizedCourseLevel(course.level),
                          style: TextStyle(
                            color: AppColors.surfaceLight,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    // XP badge - top right
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.orange, AppColors.orange],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFF59E0B,
                              ).withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppColors.surfaceLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'profile.xpValue'.tr(
                                namedArgs: {'xp': '${course.totalXp}'},
                              ),
                              style: TextStyle(
                                color: AppColors.surfaceLight,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Course title overlay at bottom
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Text(
                        course.title,
                        style: TextStyle(
                          color: AppColors.surfaceLight,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: AppColors.backgroundDark.withValues(
                                alpha: 0.75,
                              ),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom section with info and action
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Info chips row
                    Row(
                      children: [
                        _buildInfoChip(
                          icon: Icons.menu_book_rounded,
                          label: 'profile.lessonsCount'.tr(
                            namedArgs: {'count': '${course.totalLessons}'},
                          ),
                          color: AppColorRoles.primary(isDark),
                        ),
                        const SizedBox(width: 8),
                        _buildInfoChip(
                          icon: Icons.translate_rounded,
                          label: course.language,
                          color: AppColors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Action button
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: levelColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: levelColor.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_circle_filled_rounded,
                            size: 20,
                            color: AppColors.surfaceLight,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'home.startLearning'.tr(),
                            style: TextStyle(
                              color: AppColors.surfaceLight,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedCourseThumbnail(
    BuildContext context,
    CourseEntity course,
    Color levelColor, [
    int index = 0,
  ]) {
    final candidates = buildCourseCardThumbnailCandidates(course);
    if (index >= candidates.length) {
      return _buildFeaturedCourseThumbnailPlaceholder(context, levelColor);
    }

    return CachedNetworkImage(
      imageUrl: candidates[index],
      fit: BoxFit.cover,
      placeholder: (_, __) =>
          Container(color: levelColor.withValues(alpha: 0.1)),
      errorWidget: (_, __, ___) =>
          _buildFeaturedCourseThumbnail(context, course, levelColor, index + 1),
    );
  }

  Widget _buildFeaturedCourseThumbnailPlaceholder(
    BuildContext context,
    Color levelColor,
  ) {
    return Container(
      color: levelColor.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.school_rounded,
          size: 40,
          color: AppColors.surfaceLight,
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(String level, {bool isDark = false}) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return AppColors.greenSuccessBright;
      case 'elementary':
        return AppColors.greenSuccessSoft;
      case 'intermediate':
        return AppColors.orange;
      case 'upper-intermediate':
        return AppColors.orange;
      case 'advanced':
        return AppColors.dangerGradient[0];
      default:
        return AppColorRoles.primary(isDark);
    }
  }

  String _localizedCourseLevel(String level) {
    switch (level.toLowerCase()) {
      case 'beginner':
        return 'course.difficulty.beginner'.tr();
      case 'elementary':
        return 'course.difficulty.elementary'.tr();
      case 'intermediate':
        return 'course.difficulty.intermediate'.tr();
      case 'upper-intermediate':
        return 'course.difficulty.upperIntermediate'.tr();
      case 'advanced':
        return 'course.difficulty.advanced'.tr();
      default:
        return level;
    }
  }

  /// Quick Actions - Horizontal scrollable section with circular buttons
  Widget _buildQuickActionsHorizontal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    // Keep all dark-mode quick actions in a consistent neon range.
    const neonDarkActionColors = <Color>[
      Color(0xFFFF3131), // YouTube
      Color(0xFFFC1AD3), // News
      Color(0xFFFFA319), // Games
      Color(0xFF35FF0D), // Podcast
      Color(0xFF8B5CFF), // Books (neon purple)
      Color(0xFFFF369E), // Vocabulary
    ];

    final quickActions = [
      {
        'icon': Icons.smart_display,
        'label': 'home.youtube',
        'color': isDark ? neonDarkActionColors[0] : AppColors.dangerGradient[0],
        'bgColor':
            (isDark ? neonDarkActionColors[0] : AppColors.dangerGradient[0])
                .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/youtube',
      },
      {
        'icon': Icons.article,
        'label': 'home.news',
        'color': isDark ? neonDarkActionColors[1] : AppColors.teal,
        'bgColor': (isDark ? neonDarkActionColors[1] : AppColors.teal)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/news',
      },
      {
        'icon': Icons.sports_esports,
        'label': 'home.games',
        'color': isDark ? neonDarkActionColors[2] : AppColors.purple,
        'bgColor': (isDark ? neonDarkActionColors[2] : AppColors.purple)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/games',
      },
      {
        'icon': Icons.podcasts,
        'label': 'home.podcast',
        'color': isDark ? neonDarkActionColors[3] : accent,
        'bgColor': (isDark ? neonDarkActionColors[3] : accent).withValues(
          alpha: isDark ? 0.16 : 0.12,
        ),
        'route': '/podcast',
      },
      {
        'icon': Icons.menu_book_rounded,
        'label': 'home.books',
        'color': isDark ? neonDarkActionColors[4] : AppColors.purpleLight,
        'bgColor': (isDark ? neonDarkActionColors[4] : AppColors.purple)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/books',
      },
      {
        'icon': Icons.style,
        'label': 'home.vocabulary',
        'color': isDark ? neonDarkActionColors[5] : AppColors.orange,
        'bgColor': (isDark ? neonDarkActionColors[5] : AppColors.warning)
            .withValues(alpha: isDark ? 0.16 : 0.1),
        'route': '/vocab',
      },
    ];

    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: quickActions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final action = quickActions[index];
          return _buildQuickActionChip(
            context,
            icon: action['icon'] as IconData,
            label: (action['label'] as String).tr(),
            color: action['color'] as Color,
            bgColor: action['bgColor'] as Color,
            onTap: () {
              final route = action['route'] as String;
              if (route == '/vocab') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VocabLibraryPage()),
                );
              } else {
                Navigator.pushNamed(context, route);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildQuickActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.42 : 0.3),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: isDark ? 0.46 : 0.3),
                    blurRadius: isDark ? 11 : 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.surface,
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildQuickStats(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = [
      _QuickStat(
        icon: Icons.article_rounded,
        label: 'home.articles'.tr(),
        value: '—',
        color: AppColorRoles.primary(isDark),
      ),
      _QuickStat(
        icon: Icons.sports_esports_rounded,
        label: 'home.games'.tr(),
        value: '—',
        color: AppColors.purple,
      ),
      _QuickStat(
        icon: Icons.headphones_rounded,
        label: 'home.listened'.tr(),
        value: '—',
        color: AppColorRoles.primary(isDark),
      ),
      _QuickStat(
        icon: Icons.menu_book_rounded,
        label: 'home.reading'.tr(),
        value: '—',
        color: AppColors.greenSuccessBright,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: stats
            .expand(
              (s) => [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDarkElevated
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: s.color.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(s.icon, color: s.color, size: 22),
                        const SizedBox(height: 4),
                        Text(
                          s.value,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            )
            .take(stats.length * 2 - 1)
            .toList(),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildContinueSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<BookProvider>(
      builder: (context, bookProvider, _) {
        final currentBook = bookProvider.currentBook;
        final currentProgress = bookProvider.currentProgress;

        final items = <_ContinueItem>[
          _ContinueItem(
            icon: Icons.smart_display_rounded,
            title: 'home.youtube'.tr(),
            subtitle: 'home.continueWatching'.tr(),
            color: AppColors.dangerGradient[0],
            route: '/youtube',
          ),
          _ContinueItem(
            icon: Icons.article_rounded,
            title: 'home.news'.tr(),
            subtitle: 'home.continueReading'.tr(),
            color: AppColorRoles.primary(isDark),
            route: '/news',
          ),
          _ContinueItem(
            icon: Icons.sports_esports_rounded,
            title: 'home.games'.tr(),
            subtitle: 'home.earnMoreXp'.tr(),
            color: AppColors.purple,
            route: '/games',
          ),
          _ContinueItem(
            icon: Icons.podcasts_rounded,
            title: 'home.podcast'.tr(),
            subtitle: 'home.continueListening'.tr(),
            color: AppColorRoles.primary(isDark),
            route: '/podcast',
          ),
          if (currentBook != null)
            _ContinueItem(
              icon: Icons.menu_book_rounded,
              title: currentBook.title.length > 18
                  ? '${currentBook.title.substring(0, 18)}…'
                  : currentBook.title,
              subtitle: currentProgress != null
                  ? 'home.percentRead'.tr(
                      namedArgs: {
                        'percent':
                            '${(currentProgress.readingProgress * 100).toInt()}',
                      },
                    )
                  : 'home.continueReading'.tr(),
              color: AppColors.greenSuccessBright,
              route: '/books',
            )
          else
            _ContinueItem(
              icon: Icons.menu_book_rounded,
              title: 'home.books'.tr(),
              subtitle: 'home.startReading'.tr(),
              color: AppColors.greenSuccessBright,
              route: '/books',
            ),
        ];

        return SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final item = items[i];
              return GestureDetector(
                onTap: () => Navigator.pushNamed(context, item.route),
                child: Container(
                  width: 130,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceDarkElevated
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.color.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(item.icon, color: item.color, size: 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: AppColorRoles.textPrimary(isDark),
        ),
      ),
    );
  }

  /// Build skeleton loading state for home page
  Widget _buildSkeletonLoading() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton
          ShimmerContainer(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const SkeletonCircle(size: 48),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 150, height: 14),
                      SizedBox(height: 6),
                      SkeletonText(width: 100, height: 12),
                      SizedBox(height: 6),
                      SkeletonText(width: 120, height: 18),
                    ],
                  ),
                  const Spacer(),
                  const SkeletonCircle(size: 40),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Streak card skeleton
          const SkeletonProgressStats(),
          const SizedBox(height: 24),
          // Daily goal skeleton
          ShimmerContainer(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 16),
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Section title skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ShimmerContainer(
              child: SkeletonText(width: 150, height: 20),
            ),
          ),
          const SizedBox(height: 12),
          // Courses skeleton
          const SkeletonHomeSection(),
          const SizedBox(height: 24),
          // Another section
          const SkeletonHomeSection(),
        ],
      ),
    );
  }
}

class _QuickStat {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _QuickStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _ContinueItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String route;

  const _ContinueItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.route,
  });
}
