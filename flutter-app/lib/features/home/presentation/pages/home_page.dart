import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/enrolled_courses_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/featured_courses_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/home_header.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/home_skeleton_loading.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/level_and_daily_goal_row.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/quick_actions_grid.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/section_title.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/streak_card_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_section.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/daily_review_card.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_challenges_widget.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_reward_dialog.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/level_up_dialog.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_up_dialog.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/word_of_day_card.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/active_boosts_bar.dart';

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
        if (mounted) _levelProvider?.fetchLevelFull();
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
    if (streak != null &&
        streak.isDailyRewardAvailable &&
        !_isDailyRewardDialogShowing) {
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
              return const HomeSkeletonLoading();
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
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: StaggeredList(
                  itemDelay: const Duration(milliseconds: 55),
                  itemDuration: const Duration(milliseconds: 460),
                  slideOffset: 22,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: HomeHeader(),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: StreakCardSection(),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle(title: 'home.quickActions'.tr()),
                          const SizedBox(height: 8),
                          const QuickActionsGrid(),
                        ],
                      ),
                    ),
                    const TodayPlanSection(),
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: ActiveBoostsBar(),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: WordOfDayCard(),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LevelAndDailyGoalRow(),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: DailyChallengesCard(),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: DailyReviewCard(),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle(
                            title: 'home.continueLearningSection'.tr(),
                          ),
                          const SizedBox(height: 8),
                          const EnrolledCoursesSection(),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle(title: 'home.featuredCourses'.tr()),
                          const SizedBox(height: 8),
                          const FeaturedCoursesSection(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
