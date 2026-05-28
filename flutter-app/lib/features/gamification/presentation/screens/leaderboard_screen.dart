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
    'sapphire',
    'ruby',
    'amethyst',
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
    return Consumer<GamificationProvider>(
      builder: (context, provider, child) {
        final isMaster = provider.selectedLeague.toLowerCase() == 'master';
        final showLeagueCard = provider.leagueStatus != null;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'leaderboard.title'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: () => _showRankInfoDialog(context),
              ),
            ],
          ),
          body: Column(
            children: [
              if (showLeagueCard)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: LeagueCard(
                    status: provider.leagueStatus!,
                    onTap: () {
                      // Jump to user's league tab
                      final index = _leagues.indexOf(
                        provider.leagueStatus!.league.toLowerCase(),
                      );
                      if (index >= 0) {
                        _tabController.animateTo(index);
                      }
                    },
                  ),
                ),
              TabBar(
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
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    const backgroundAspectRatio = 941 / 1672;
                    final backgroundHeight = width / backgroundAspectRatio;

                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: backgroundHeight,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isMaster
                                    ? [
                                        const Color(
                                          0xFF5AB6FF,
                                        ).withValues(alpha: 0.35),
                                        const Color(
                                          0xFFFFD64F,
                                        ).withValues(alpha: 0.25),
                                        Theme.of(
                                          context,
                                        ).scaffoldBackgroundColor,
                                      ]
                                    : [
                                        _getLeagueColor(
                                          provider.selectedLeague,
                                        ).withValues(alpha: 0.25),
                                        Theme.of(
                                          context,
                                        ).scaffoldBackgroundColor,
                                      ],
                                stops: isMaster
                                    ? const [0.0, 0.4, 0.9]
                                    : const [0.0, 0.8],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: backgroundHeight,
                          child: Image.asset(
                            'assets/ranking/honor-ranking.png',
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topCenter,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        TabBarView(
                          controller: _tabController,
                          children: _leagues.map((league) {
                            return _LeaderboardTab(league: league);
                          }).toList(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          // removed container
        );
      },
    );
  }

  String _getLeagueName(String league) {
    return '${league[0].toUpperCase()}${league.substring(1)}';
  }

  Color _getLeagueColor(String league) {
    return rankVisualDataFor(league).color;
  }

  void _showRankInfoDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'leaderboard.aboutLeagues'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  itemCount: _leagues.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    // Reversed list so Master is at top
                    final rank = _leagues[_leagues.length - 1 - index];
                    final visualData = rankVisualDataFor(rank);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          RankAssetIcon(rank: rank, size: 56),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                rank == 'master'
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
                                        child: Text(
                                          rankDisplayNameFor(rank),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        rankDisplayNameFor(rank),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: visualData.color,
                                        ),
                                      ),
                                const SizedBox(height: 4),
                                Text(
                                  'leaderboard.${rank}Desc'.tr(),
                                  style: TextStyle(
                                    color: AppColorRoles.textMuted(isDark),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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
        final leaderboard = provider.leaderboardFor(league);
        final isSelected =
            provider.selectedLeague.toLowerCase() == league.toLowerCase();

        if (leaderboard == null) {
          if (provider.isLoadingLeaderboard && isSelected) {
            return const Center(child: LottieLoadingWidget.medium());
          }

          if (provider.leaderboardError != null && isSelected) {
            return ErrorDisplayWidget.fromMessage(
              message: provider.leaderboardError!,
              onRetry: () => provider.loadLeaderboard(league: league),
            );
          }

          return _buildEmptyState(context);
        }

        final rankEntries = leaderboard.entries
            .where((entry) => rankVisualDataFor(entry.userRank).key == league)
            .toList();
        final topThree = rankEntries.take(3).toList();

        return LeaderboardPodium(
          league: league,
          topThree: topThree,
          entries: rankEntries,
          totalParticipants: leaderboard.totalParticipants,
          onRefresh: () async {
            await provider.loadLeaderboard(league: league);
            await provider.loadLeagueStatus();
          },
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
    final isMaster = league.toLowerCase() == 'master';

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isMaster
              ? [const Color(0xFF5AB6FF), const Color(0xFFFFD64F)]
              : [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: isMaster
                ? const Color(0xFF5AB6FF).withValues(alpha: 0.3)
                : color.withValues(alpha: 0.3),
            blurRadius: 4,
          ),
        ],
      ),
      child: RankAssetIcon(rank: league, size: 16, decorated: false),
    );
  }
}
