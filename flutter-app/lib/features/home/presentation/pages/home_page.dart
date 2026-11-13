import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/promo_banner_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/discover_rail.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/home_header.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/home_skeleton_loading.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/next_up_hero.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/progress_chips_row.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/promo_banner_section.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/quick_actions_grid.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/section_title.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/streak_goal_strip.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_reward_dialog.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/level_up_dialog.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_up_dialog.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/word_of_day_card.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeProvider = context.read<HomeProvider>();
      // Captured synchronously so dispose() can remove the listener without
      // touching context after an async gap.
      _levelProvider = context.read<LevelProvider>();
      homeProvider.loadHomeData().then((_) {
        if (mounted) _levelProvider?.fetchLevelFull();
      });
      context.read<PromoBannerProvider>().load();
      _levelProvider?.addListener(_onLevelProviderChange);

      _streakProvider = context.read<StreakProvider>();
      _streakProvider?.addListener(_onStreakProviderChange);
      // Loaded here, after the auth token is ready, rather than in main.dart.
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
    if (streakProvider == null || !mounted) return;

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

  void _onLevelProviderChange() {
    final levelProvider = _levelProvider;
    if (levelProvider == null || !mounted) return;

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
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).scaffoldBackgroundColor
          : AppColors.skyBackground,
      body: SafeArea(
        bottom: false,
        child: Consumer3<HomeProvider, UserProvider, AuthProvider>(
          builder: (context, homeProvider, userProvider, authProvider, child) {
            final hasContent =
                homeProvider.featuredCourses.isNotEmpty ||
                homeProvider.enrolledCourses.isNotEmpty;

            if (homeProvider.isLoading && !hasContent) {
              return const HomeSkeletonLoading();
            }

            // A failed fetch replaces the page only when there is nothing to
            // show; with data on screen the discover rail carries the retry.
            if (homeProvider.errorMessage != null && !hasContent) {
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
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: StaggeredList(
                      itemDelay: const Duration(milliseconds: 55),
                      itemDuration: const Duration(milliseconds: 460),
                      slideOffset: 22,
                      children: [
                        const HomeHeader(),
                        const NextUpHero(),
                        const StreakGoalStrip(),
                        const ProgressChipsRow(),
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionTitle(title: 'home.quickActions'.tr()),
                              const SizedBox(height: 8),
                              const QuickActionsGrid(),
                            ],
                          ),
                        ),
                        const WordOfDayCard(),
                        const PromoBannerSection(),
                        const DiscoverRail(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
