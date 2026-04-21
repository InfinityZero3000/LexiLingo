import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/leaderboard_podium.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/league_card.dart';

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
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _leagues.length, vsync: this);
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<GamificationProvider>();
      provider.loadLeaderboard();
      provider.loadLeagueStatus();
    });
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
              final showLeagueCard = provider.leagueStatus != null &&
                  provider.selectedLeague == provider.leagueStatus!.league;
              return [
                // App Bar
                SliverAppBar(
                  title: const Text('Leaderboard'),
                  centerTitle: true,
                  pinned: true,
                  floating: true,
                  expandedHeight: showLeagueCard ? 200 : 120,
                  flexibleSpace: FlexibleSpaceBar(
                    background: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getLeagueColor(
                              provider.selectedLeague,
                              isDark,
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
                                child: LeagueCard(
                                  status: provider.leagueStatus!,
                                  onTap: () {
                                    // Jump to user's league tab
                                    final index = _leagues.indexOf(
                                      provider.leagueStatus!.league,
                                    );
                                    if (index >= 0) {
                                      _tabController.animateTo(index);
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  bottom: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: primaryColor,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    indicatorColor: primaryColor,
                    tabs: _leagues.map((league) {
                      return Tab(
                        child: Row(
                          children: [
                            _LeagueBadgeSmall(league: league),
                            const SizedBox(width: 6),
                            Text(_getLeagueName(league)),
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

  Color _getLeagueColor(String league, bool isDark) {
    switch (league.toLowerCase()) {
      case 'bronze':
        return AppColors.orange;
      case 'silver':
        return AppColors.textMuted;
      case 'gold':
        return AppColors.warning;
      case 'platinum':
        return AppColors.purple;
      case 'diamond':
        return AppColorRoles.primary(isDark);
      default:
        return AppColors.orange;
    }
  }
}

/// Individual League Tab Content
class _LeaderboardTab extends StatelessWidget {
  final String league;

  const _LeaderboardTab({required this.league});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Consumer<GamificationProvider>(
      builder: (context, provider, child) {
        // Only show content for the selected league
        if (provider.selectedLeague != league) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.isLoadingLeaderboard && provider.leaderboard == null) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.leaderboardError != null && provider.leaderboard == null) {
          return ErrorDisplayWidget.fromMessage(
            message: provider.leaderboardError!,
            onRetry: () => provider.loadLeaderboard(league: league),
          );
        }

        final leaderboard = provider.leaderboard;
        if (leaderboard == null || leaderboard.entries.isEmpty) {
          return _buildEmptyState(context);
        }

        final topThree = leaderboard.topThree;
        final remaining = leaderboard.entries.skip(3).toList();

        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadLeaderboard(league: league);
            await provider.loadLeagueStatus();
          },
          child: CustomScrollView(
            slivers: [
              // Week info
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Week ends ${_formatDate(leaderboard.weekEnd)}',
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${leaderboard.totalParticipants} participants',
                        style: TextStyle(
                          color: AppColorRoles.textMuted(isDark),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Podium for top 3
              if (topThree.isNotEmpty)
                SliverToBoxAdapter(
                  child: LeaderboardPodium(topThree: topThree),
                ),

              // Divider
              if (remaining.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'More Ranks',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final entry = remaining[index];
                  return LeaderboardEntryRow(
                    entry: entry,
                    onTap: () {
                      // Navigate to user profile
                    },
                  );
                }, childCount: remaining.length),
              ),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
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
            'No rankings yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColorRoles.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to compete this week!',
            style: TextStyle(color: AppColorRoles.textMuted(isDark)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);

    if (diff.inDays > 1) {
      return 'in ${diff.inDays} days';
    } else if (diff.inHours > 0) {
      return 'in ${diff.inHours} hours';
    } else {
      return 'soon';
    }
  }
}

/// Small league badge for tabs
class _LeagueBadgeSmall extends StatelessWidget {
  final String league;

  const _LeagueBadgeSmall({required this.league});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _getLeagueColor(league, isDark);

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
      child: Icon(
        _getLeagueIcon(league),
        color: Theme.of(context).colorScheme.surface,
        size: 12,
      ),
    );
  }

  Color _getLeagueColor(String league, bool isDark) {
    switch (league.toLowerCase()) {
      case 'bronze':
        return AppColors.orange;
      case 'silver':
        return AppColors.textMuted;
      case 'gold':
        return AppColors.warning;
      case 'platinum':
        return AppColors.purple;
      case 'diamond':
        return AppColorRoles.primary(isDark);
      default:
        return AppColors.orange;
    }
  }

  IconData _getLeagueIcon(String league) {
    switch (league.toLowerCase()) {
      case 'bronze':
        return Icons.shield_outlined;
      case 'silver':
        return Icons.shield;
      case 'gold':
        return Icons.emoji_events_outlined;
      case 'platinum':
        return Icons.emoji_events;
      case 'diamond':
        return Icons.diamond;
      default:
        return Icons.shield_outlined;
    }
  }
}
