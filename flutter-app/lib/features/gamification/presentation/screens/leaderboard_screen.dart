import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/leaderboard_podium.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/league_card.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_asset_icon.dart';

/// Leaderboard Screen
/// Displays weekly leaderboard rankings by league
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<String> _leagues = [
    'bronze',
    'silver',
    'gold',
    'platinum',
    'diamond',
    'master',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _leagues.length, vsync: this);
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialRankTab();
    });
  }

  Future<void> _loadInitialRankTab() async {
    final provider = context.read<GamificationProvider>();
    await provider.loadLeagueStatus();
    if (!mounted) return;

    final currentLeague = provider.leagueStatus?.league.toLowerCase();
    final league = _leagues.contains(currentLeague)
        ? currentLeague!
        : _leagues.first;
    final index = _leagues.indexOf(league);

    if (_tabController.index == index) {
      await provider.loadLeaderboard(league: league);
      return;
    }

    _tabController.animateTo(index);
  }

  void _onTabChanged() {
    final league = _leagues[_tabController.index];
    context.read<GamificationProvider>().setLeague(league);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Scaffold(
      body: Consumer<GamificationProvider>(
        builder: (context, provider, child) {
          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              final showLeagueCard = provider.leagueStatus != null;
              return [
                // App Bar
                SliverAppBar(
                  title: Text('leaderboard.title'.tr()),
                  centerTitle: true,
                  pinned: true,
                  floating: true,
                  expandedHeight: showLeagueCard ? 256 : 120,
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      final top = constraints.biggest.height;
                      final minHeight = MediaQuery.of(context).padding.top +
                          kToolbarHeight +
                          48; // TabBar height
                      final maxHeight = showLeagueCard ? 256.0 : 120.0;
                      final delta = maxHeight - minHeight;
                      final t = delta > 0.0
                          ? ((top - minHeight) / delta).clamp(0.0, 1.0)
                          : 0.0;

                      final scale = 0.8 + (0.2 * t);
                      final blur = (1 - t) * 10.0;
                      final opacity = Curves.easeIn.transform(t);

                      return FlexibleSpaceBar(
                        background: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _getLeagueColor(
                                  provider.selectedLeague,
                                ).withValues(alpha: 0.3),
                                Theme.of(context).scaffoldBackgroundColor,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: SafeArea(
                            child: Column(
                              children: [
                                const SizedBox(height: 56), // AppBar height
                                if (showLeagueCard)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Opacity(
                                      opacity: opacity,
                                      child: Transform.scale(
                                        scale: scale,
                                        child: ImageFiltered(
                                          imageFilter: ImageFilter.blur(
                                            sigmaX: blur,
                                            sigmaY: blur,
                                          ),
                                          child: LeagueCard(
                                            status: provider.leagueStatus!,
                                            onTap: () {
                                              // Jump to user's league tab
                                              final index = _leagues.indexOf(
                                                provider.leagueStatus!.league
                                                    .toLowerCase(),
                                              );
                                              if (index >= 0) {
                                                _tabController.animateTo(index);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (showLeagueCard) const SizedBox(height: 62),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  bottom: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: primaryColor,
                    unselectedLabelColor: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
                    indicatorColor: primaryColor,
                    tabs: _leagues.map((league) {
                      final isCurrentLeague =
                          provider.leagueStatus?.league.toLowerCase() == league;
                      return Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LeagueBadgeSmall(league: league),
                            const SizedBox(width: 6),
                            Text(_getLeagueName(league)),
                            if (isCurrentLeague) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: _leagues.map((league) {
                return _LeaderboardTab(league: league);
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  String _getLeagueName(String league) {
    return '${league[0].toUpperCase()}${league.substring(1)}';
  }

  Color _getLeagueColor(String league) {
    return rankVisualDataFor(league).color;
  }
}

/// Individual League Tab Content
class _LeaderboardTab extends StatelessWidget {
  final String league;

  const _LeaderboardTab({required this.league});

  @override
  Widget build(BuildContext context) {
    return Consumer<GamificationProvider>(
      builder: (context, provider, child) {
        // Only show content for the selected league
        if (provider.selectedLeague != league) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        final leaderboard = provider.leaderboard;
        final hasMatchingLeaderboard =
            leaderboard?.league.toLowerCase() == league;

        if (provider.isLoadingLeaderboard && !hasMatchingLeaderboard) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.leaderboardError != null && !hasMatchingLeaderboard) {
          return ErrorDisplayWidget.fromMessage(
            message: provider.leaderboardError!,
            onRetry: () => provider.loadLeaderboard(league: league),
          );
        }

        if (leaderboard == null || !hasMatchingLeaderboard) {
          return _buildEmptyState(context);
        }

        final rankEntries = leaderboard.entries
            .where((entry) => entry.userRank.toLowerCase() == league)
            .toList();
        final topThree = rankEntries.take(3).toList();

        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadLeaderboard(league: league);
            await provider.loadLeagueStatus();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                fillOverscroll: true,
                child: LeaderboardPodium(
                  league: league,
                  topThree: topThree,
                  entries: rankEntries,
                  totalParticipants: leaderboard.totalParticipants,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined, size: 64, color: AppColors.grey400),
          const SizedBox(height: 16),
          Text(
            'leaderboard.noRankingsYet'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColorRoles.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'leaderboard.firstToCompete'.tr(),
            style: TextStyle(color: AppColorRoles.textMuted(isDark)),
          ),
        ],
      ),
    );
  }
}

/// Small league badge for tabs
class _LeagueBadgeSmall extends StatelessWidget {
  final String league;

  const _LeagueBadgeSmall({required this.league});

  @override
  Widget build(BuildContext context) {
    final color = rankVisualDataFor(league).color;

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4),
        ],
      ),
      child: RankAssetIcon(rank: league, size: 16, decorated: false),
    );
  }
}
