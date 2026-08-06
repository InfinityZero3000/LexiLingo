import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/leaderboard_podium.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/league_card.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_asset_icon.dart';
import 'package:lexilingo_app/features/gamification/presentation/screens/league_ceremony_screen.dart';

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
  bool _didPrecacheRankingAssets = false;
  bool _isLoadingInitialRankTab = true;
  LeaderboardEntryEntity? _selectedLeaderboardEntry;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didPrecacheRankingAssets) return;
    _didPrecacheRankingAssets = true;

    precacheImage(
      const AssetImage('assets/ranking/honor-ranking.png'),
      context,
    );
    for (final league in _leagues) {
      precacheImage(AssetImage(rankVisualDataFor(league).assetPath), context);
    }
  }

  Future<void> _loadInitialRankTab() async {
    final provider = context.read<GamificationProvider>();
    try {
      await provider.loadLeagueStatus();
      if (!mounted) return;

      // Show league ceremony if the user was promoted/demoted since last session.
      final from = provider.leagueChangedFrom;
      final to = provider.leagueChangedTo;
      if (from != null && to != null) {
        final leagueOrder = LeagueStatusEntity.leagueOrder;
        final fromIndex = leagueOrder.indexOf(from);
        final toIndex = leagueOrder.indexOf(to);
        final ceremonyType = toIndex > fromIndex
            ? LeagueCeremonyType.promotion
            : LeagueCeremonyType.demotion;
        await LeagueCeremonyScreen.show(
          context,
          newLeague: to,
          previousLeague: from,
          type: ceremonyType,
          onContinue: () {},
        );
        // Clear after the ceremony resolves regardless of how it was dismissed.
        provider.clearLeagueChange();
        if (!mounted) return;
      }

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
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInitialRankTab = false;
        });
      }
    }
  }

  void _onTabChanged() {
    final league = _leagues[_tabController.index];
    context.read<GamificationProvider>().setLeague(league);
    setState(() {
      _selectedLeaderboardEntry = null;
    });
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
        final isBootstrapping =
            _isLoadingInitialRankTab ||
            (provider.isLoadingLeagueStatus && provider.leagueStatus == null);
        final showLeagueCard = provider.leagueStatus != null || isBootstrapping;

        return AnimatedContainer(
          duration: isBootstrapping
              ? Duration.zero
              : const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isMaster
                  ? [
                      AppColors.masterGradient[0].withValues(alpha: 0.35),
                      AppColors.masterGradient[1].withValues(alpha: 0.25),
                      Theme.of(context).scaffoldBackgroundColor,
                    ]
                  : [
                      _getLeagueColor(
                        provider.selectedLeague,
                      ).withValues(alpha: 0.25),
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
              stops: isMaster ? const [0.0, 0.4, 0.9] : const [0.0, 0.8],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(
                'leaderboard.title'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              centerTitle: true,
              actions: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: _RankHelpButton(
                    onPressed: () => _showRankInfoDialog(context),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                if (showLeagueCard)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: provider.leagueStatus == null
                        ? const _LeagueCardSkeleton()
                        : LeagueCard(
                            status: provider.leagueStatus!,
                            selectedEntry: _selectedLeaderboardEntry,
                            onTap: () {
                              if (_selectedLeaderboardEntry != null) {
                                // Deselect and revert to current user's card
                                setState(() {
                                  _selectedLeaderboardEntry = null;
                                });
                                return;
                              }
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
                            child: Image.asset(
                              'assets/ranking/honor-ranking.png',
                              fit: BoxFit.fitWidth,
                              alignment: Alignment.topCenter,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          TabBarView(
                            controller: _tabController,
                            children: _leagues.map((league) {
                              return _LeaderboardTab(
                                league: league,
                                isBootstrapping: isBootstrapping,
                                onEntrySelected: (entry) {
                                  setState(() {
                                    _selectedLeaderboardEntry = entry;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
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
                  color: isDark ? AppColors.grey700 : AppColors.grey300,
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
                                              colors: AppColors.masterGradient,
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ).createShader(bounds),
                                        child: Text(
                                          rankDisplayNameFor(rank),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.surfaceLight,
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
  final bool isBootstrapping;
  final void Function(LeaderboardEntryEntity?)? onEntrySelected;

  const _LeaderboardTab({
    required this.league,
    required this.isBootstrapping,
    this.onEntrySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GamificationProvider>(
      builder: (context, provider, child) {
        final leaderboard = provider.leaderboardFor(league);
        final isSelected =
            provider.selectedLeague.toLowerCase() == league.toLowerCase();

        if (leaderboard == null) {
          if (isSelected &&
              (isBootstrapping || provider.isLoadingLeaderboardFor(league))) {
            return const _LeaderboardSkeleton();
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
          onEntrySelected: onEntrySelected,
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

class _RankHelpButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RankHelpButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = AppColorRoles.textPrimary(isDark);
    final accent = AppColorRoles.primary(isDark);
    final label = 'leaderboard.aboutLeagues'.tr();

    return IconButton(
      tooltip: label,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: isDark ? 0.24 : 0.86),
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: 0.42), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          '?',
          style: TextStyle(
            color: foreground,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _LeagueCardSkeleton extends StatelessWidget {
  const _LeagueCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ShimmerContainer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: isDark ? 0.44 : 0.74),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.12),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const SkeletonBox(width: 112, height: 112, borderRadius: 56),
            const SizedBox(width: 26),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SkeletonText(width: 150, height: 20),
                  const SizedBox(height: 10),
                  SkeletonText(
                    width: MediaQuery.of(context).size.width * 0.42,
                    height: 14,
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      SkeletonBox(width: 78, height: 24, borderRadius: 999),
                      SizedBox(width: 8),
                      SkeletonBox(width: 64, height: 24, borderRadius: 999),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const SkeletonText(width: 112, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardSkeleton extends StatelessWidget {
  const _LeaderboardSkeleton();

  static const _backgroundAspectRatio = 941 / 1672;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final backgroundHeight = width / _backgroundAspectRatio;

        return ShimmerContainer(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                _buildHonorSlot(
                  canvasWidth: width,
                  backgroundHeight: backgroundHeight,
                  rank: 1,
                  centerX: 0.5,
                  centerY: 0.17,
                ),
                _buildHonorSlot(
                  canvasWidth: width,
                  backgroundHeight: backgroundHeight,
                  rank: 2,
                  centerX: 0.265,
                  centerY: 0.368,
                ),
                _buildHonorSlot(
                  canvasWidth: width,
                  backgroundHeight: backgroundHeight,
                  rank: 3,
                  centerX: 0.735,
                  centerY: 0.368,
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  height: (height * 0.38).clamp(240.0, 340.0),
                  child: const _RankingPanelSkeleton(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHonorSlot({
    required int rank,
    required double canvasWidth,
    required double backgroundHeight,
    required double centerX,
    required double centerY,
  }) {
    final avatarSize = (canvasWidth * (rank == 1 ? 0.255 : 0.185))
        .clamp(rank == 1 ? 86.0 : 64.0, rank == 1 ? 150.0 : 98.0)
        .toDouble();
    final labelWidth = (avatarSize * (rank == 1 ? 1.58 : 1.76))
        .clamp(112.0, rank == 1 ? 166.0 : 150.0)
        .toDouble();
    final left = canvasWidth * centerX - labelWidth / 2;
    final top = backgroundHeight * centerY - avatarSize / 2;

    return Positioned(
      left: left,
      top: top,
      width: labelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(
            width: avatarSize,
            height: avatarSize,
            borderRadius: avatarSize / 2,
          ),
          const SizedBox(height: 13),
          SkeletonBox(width: labelWidth * 0.78, height: 28, borderRadius: 14),
        ],
      ),
    );
  }
}

class _RankingPanelSkeleton extends StatelessWidget {
  const _RankingPanelSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelColor = isDark
        ? AppColors.surfaceDark.withValues(alpha: 0.72)
        : AppColors.surfaceLight.withValues(alpha: 0.82);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: AppColors.surfaceLight.withValues(alpha: 0.42),
            ),
            left: BorderSide(
              color: AppColors.surfaceLight.withValues(alpha: 0.42),
            ),
            right: BorderSide(
              color: AppColors.surfaceLight.withValues(alpha: 0.42),
            ),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                children: [
                  const SkeletonBox(width: 40, height: 4, borderRadius: 2),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SkeletonBox(width: 34, height: 34, borderRadius: 17),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonText(width: 132, height: 16),
                            SizedBox(height: 6),
                            SkeletonText(width: 78, height: 11),
                          ],
                        ),
                      ),
                      const SkeletonBox(width: 86, height: 18, borderRadius: 9),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: 4,
                itemBuilder: (context, index) {
                  return const _RankingRowSkeleton();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingRowSkeleton extends StatelessWidget {
  const _RankingRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SkeletonBox(width: 32, height: 32, borderRadius: 16),
          const SizedBox(width: 10),
          const SkeletonBox(width: 42, height: 42, borderRadius: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(
                  width: MediaQuery.of(context).size.width * 0.34,
                  height: 14,
                ),
                const SizedBox(height: 8),
                SkeletonText(
                  width: MediaQuery.of(context).size.width * 0.24,
                  height: 12,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SkeletonBox(width: 64, height: 30, borderRadius: 999),
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
              ? AppColors.masterGradient
              : [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: isMaster
                ? AppColors.masterGradient[0].withValues(alpha: 0.3)
                : color.withValues(alpha: 0.3),
            blurRadius: 4,
          ),
        ],
      ),
      child: RankAssetIcon(rank: league, size: 16, decorated: false),
    );
  }
}
